#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   install.sh
#  Funcao:   Instalacao Completa do Ambiente (All-in-One)
#  Versao:   3.0.0
#
#  USO:
#    bash install.sh                 # Instalacao completa
#    bash install.sh --apps-only     # Somente bancos + apps (pula Docker/Traefik/Portainer)
#    bash install.sh --no-apps       # Sem aplicacoes (somente infra + bancos)
#    bash install.sh --no-databases  # Somente Docker + Traefik + Portainer
#    bash install.sh --openclaw      # Instalacao completa + OpenClaw
#    bash install.sh --tunnel        # Instalacao completa + Cloudflare Tunnel
#    bash install.sh --check         # Verifica se os servicos estao rodando
#
#==============================================================================

#==============================================================================
# PARSE DE ARGUMENTOS
#==============================================================================
NO_APPS=false
NO_DATABASES=false
APPS_ONLY=false
INSTALL_OPENCLAW=false
INSTALL_TUNNEL=false
RUN_CHECK=false

show_help() {
    echo "Uso: bash install.sh [OPCOES]"
    echo ""
    echo "OPCOES:"
    echo "  --apps-only       Instala somente bancos + apps (pula Docker/Traefik/Portainer)"
    echo "                    Ideal para reinstalar apps apos limpeza (98-limpeza-apps.sh)"
    echo ""
    echo "  --no-apps         Nao instala aplicacoes (n8n, Chatwoot, Evolution, WordPress)"
    echo "                    Instala: Docker, Traefik, Portainer + Bancos de Dados"
    echo ""
    echo "  --no-databases    Nao instala bancos de dados nem aplicacoes"
    echo "                    Instala: Docker, Traefik, Portainer"
    echo "                    (implica --no-apps, pois apps dependem dos bancos)"
    echo ""
    echo "  --openclaw        Inclui o deploy do OpenClaw (AI Assistant)"
    echo "                    Pode ser combinado com outros parametros"
    echo ""
    echo "  --tunnel          Configura Cloudflare Tunnel para acesso externo"
    echo "                    Requer CF_ACCOUNT_ID e CF_TUNNEL_API_TOKEN no .env"
    echo ""
    echo "  --check           Verifica se todos os servicos estao rodando"
    echo "                    Nao instala nada, apenas diagnostica o ambiente"
    echo ""
    echo "  -h, --help        Exibe esta ajuda"
    echo ""
    echo "Sem opcoes: instalacao completa de todos os servicos (sem OpenClaw/Tunnel)."
}

for arg in "$@"; do
    case $arg in
        --apps-only)    APPS_ONLY=true ;;
        --no-apps)      NO_APPS=true ;;
        --no-databases) NO_DATABASES=true; NO_APPS=true ;;
        --openclaw)     INSTALL_OPENCLAW=true ;;
        --tunnel)       INSTALL_TUNNEL=true ;;
        --check)        RUN_CHECK=true ;;
        -h|--help)      show_help; exit 0 ;;
        *)              echo "[ERRO] Parametro desconhecido: $arg"; show_help; exit 1 ;;
    esac
done

#==============================================================================
# FUNCAO: MERGE DE YAMLS
# Combina multiplos arquivos YAML Docker Compose em um unico documento.
# Necessario porque a API do Portainer nao suporta multi-document YAML (---).
# Uso: merge_yaml <output> <input1> <input2> [input3...]
#==============================================================================
merge_yaml() {
    local output="$1"
    shift
    local inputs=("$@")

    # Para cada arquivo, extrai somente as linhas do bloco "services:" (indentadas)
    # e ignora as linhas do bloco "networks:" e comentarios top-level
    {
        echo "services:"
        for f in "${inputs[@]}"; do
            # Extrai o conteudo entre "services:" e "networks:" (ou EOF)
            sed -n '/^services:/,/^networks:/{ /^services:/d; /^networks:/d; p; }' "$f"
        done
        echo "networks:"
        echo "  network_public:"
        echo "    external: true"
    } > "$output"
}

#==============================================================================
# FUNCAO: CHECK DE SERVICOS
# Verifica se todos os servicos estao rodando corretamente
#==============================================================================
run_check() {
    echo "=============================================================================="
    echo "  VERIFICACAO DO AMBIENTE"
    echo "  Data: $(date)"
    echo "=============================================================================="
    echo

    local ERRORS=0
    local WARNINGS=0
    local OK=0

    # Cores
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local CYAN='\033[0;36m'
    local NC='\033[0m'

    check_ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; OK=$((OK + 1)); }
    check_fail() { echo -e "  ${RED}[ERRO]${NC}  $1"; ERRORS=$((ERRORS + 1)); }
    check_warn() { echo -e "  ${YELLOW}[AVISO]${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

    #--------------------------------------------------------------------------
    # 1. DOCKER & SWARM
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[1/6] Docker e Swarm${NC}"
    if docker info &>/dev/null; then
        check_ok "Docker esta rodando"
    else
        check_fail "Docker nao esta rodando"
    fi

    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        check_ok "Docker Swarm esta ativo"
    else
        check_fail "Docker Swarm nao esta ativo"
    fi
    echo

    #--------------------------------------------------------------------------
    # 2. STACKS
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[2/6] Stacks${NC}"
    local EXPECTED_STACKS=("traefik" "portainer" "redis" "postgres" "minio" "mysql" "n8n" "chatwoot" "evolution" "wordpress")
    local ACTIVE_STACKS=$(docker stack ls --format '{{.Name}}' 2>/dev/null)

    for stack in "${EXPECTED_STACKS[@]}"; do
        if echo "$ACTIVE_STACKS" | grep -qw "$stack"; then
            check_ok "Stack: $stack"
        else
            check_fail "Stack ausente: $stack"
        fi
    done

    # Extras opcionais
    if echo "$ACTIVE_STACKS" | grep -qw "openclaw"; then
        check_ok "Stack: openclaw (opcional)"
    else
        check_warn "Stack openclaw nao instalada (opcional)"
    fi
    if echo "$ACTIVE_STACKS" | grep -qw "cloudflared"; then
        check_ok "Stack: cloudflared (opcional)"
    else
        check_warn "Stack cloudflared nao instalada (opcional)"
    fi
    echo

    #--------------------------------------------------------------------------
    # 3. SERVICOS (replicas)
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[3/6] Servicos e Replicas${NC}"
    local EXPECTED_SERVICES=(
        "traefik_traefik"
        "portainer_portainer"
        "redis_redis"
        "postgres_postgres"
        "minio_minio"
        "mysql_mysql"
        "n8n_n8n-editor"
        "n8n_n8n-webhook"
        "n8n_n8n-worker"
        "chatwoot_chatwoot-admin"
        "chatwoot_chatwoot-sidekiq"
        "evolution_evolution"
        "wordpress_wordpress"
    )

    for svc in "${EXPECTED_SERVICES[@]}"; do
        local replicas=$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | grep "^$svc " | awk '{print $2}')
        if [ -z "$replicas" ]; then
            check_fail "Servico ausente: $svc"
        else
            local running=$(echo "$replicas" | cut -d'/' -f1)
            local desired=$(echo "$replicas" | cut -d'/' -f2)
            if [ "$running" = "$desired" ] && [ "$running" != "0" ]; then
                check_ok "$svc ($replicas)"
            else
                check_fail "$svc ($replicas) - replicas insuficientes"
            fi
        fi
    done
    echo

    #--------------------------------------------------------------------------
    # 4. STORAGE
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[4/6] Diretorios de Storage${NC}"
    local STORAGE_DIRS=(
        "/storage/traefik"
        "/storage/portainer"
        "/storage/redis"
        "/storage/postgres"
        "/storage/minio"
        "/storage/mysql"
        "/storage/n8n"
        "/storage/chatwoot"
        "/storage/evolution"
        "/storage/wordpress"
    )
    for dir in "${STORAGE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            check_ok "$dir"
        else
            check_fail "Diretorio ausente: $dir"
        fi
    done
    echo

    #--------------------------------------------------------------------------
    # 5. CERTIFICADOS SSL
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[5/6] Certificados SSL (Traefik/Let's Encrypt)${NC}"
    local ACME_FILE="/storage/traefik/data/acme.json"
    if [ -f "$ACME_FILE" ]; then
        local EXPECTED_DOMAINS=("pn" "s3" "chat" "wf" "wb" "ws" "app")
        for sub in "${EXPECTED_DOMAINS[@]}"; do
            local full="${sub}.${DOMAIN}"
            if grep -q "$full" "$ACME_FILE" 2>/dev/null; then
                check_ok "Certificado: $full"
            else
                check_fail "Certificado ausente: $full"
            fi
        done
    else
        check_fail "Arquivo acme.json nao encontrado em $ACME_FILE"
    fi
    echo

    #--------------------------------------------------------------------------
    # 6. ACESSIBILIDADE HTTP
    #--------------------------------------------------------------------------
    echo -e "${CYAN}[6/6] Acessibilidade HTTP (via localhost)${NC}"
    local URLS=(
        "https://chat.${DOMAIN}|Chatwoot"
        "https://wf.${DOMAIN}|n8n Editor"
        "https://wb.${DOMAIN}|n8n Webhook"
        "https://ws.${DOMAIN}|Evolution"
        "https://app.${DOMAIN}|WordPress"
        "https://pn.${DOMAIN}|Portainer"
        "https://s3.${DOMAIN}|MinIO"
    )
    for entry in "${URLS[@]}"; do
        local url=$(echo "$entry" | cut -d'|' -f1)
        local name=$(echo "$entry" | cut -d'|' -f2)
        local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
        if [ "$http_code" = "000" ]; then
            check_fail "$name ($url) - sem resposta"
        elif [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            check_ok "$name ($url) - HTTP $http_code"
        elif [ "$http_code" = "404" ]; then
            check_warn "$name ($url) - HTTP 404 (servico pode estar iniciando)"
        else
            check_warn "$name ($url) - HTTP $http_code"
        fi
    done
    echo

    #--------------------------------------------------------------------------
    # RESUMO
    #--------------------------------------------------------------------------
    echo "=============================================================================="
    echo -e "  RESULTADO: ${GREEN}$OK OK${NC} | ${YELLOW}$WARNINGS avisos${NC} | ${RED}$ERRORS erros${NC}"
    if [ $ERRORS -eq 0 ]; then
        echo -e "  ${GREEN}Ambiente saudavel!${NC}"
    else
        echo -e "  ${RED}Existem $ERRORS problema(s) que precisam de atencao.${NC}"
    fi
    echo "=============================================================================="

    return $ERRORS
}

# Se --check foi passado, roda verificacao e sai
if $RUN_CHECK; then
    if [ -f .env ]; then
        set -a && source .env && set +a
    fi
    run_check
    exit $?
fi

[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

#==============================================================================
# CARREGA VARIAVEIS
#==============================================================================
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "[ERRO] Arquivo .env nao encontrado. Copie o .env.example e configure suas senhas."
    exit 1
fi

#==============================================================================
# DIRETÓRIOS DE STORAGE
#==============================================================================
if ! $NO_DATABASES; then
    mkdir -p /storage/redis/{data,logs,config} && chown -R 999:1000 /storage/redis
    mkdir -p /storage/postgres/{data,logs,config} && chown -R 999:999 /storage/postgres
    mkdir -p /storage/minio/{data,logs,config} && chown -R 1000:1000 /storage/minio
    mkdir -p /storage/mysql/{data,files,tmp} && chown -R 1001:1001 /storage/mysql
fi

if ! $NO_APPS; then
    mkdir -p /storage/n8n/{data,logs,config,nodes} && chown -R 1000:1000 /storage/n8n
    mkdir -p /storage/chatwoot/{data,logs,config} && chown -R 1000:1000 /storage/chatwoot
    mkdir -p /storage/evolution/{data,logs,config} && chown -R 1000:1000 /storage/evolution
    mkdir -p /storage/wordpress/data && chown -R 33:33 /storage/wordpress
fi

if $INSTALL_OPENCLAW; then
    mkdir -p /storage/openclaw/{config,workspace} && chown -R 1000:1000 /storage/openclaw
fi

#==============================================================================
# CALCULO DINAMICO DE ETAPAS
#==============================================================================
if $APPS_ONLY; then
    TOTAL_STEPS=0
else
    TOTAL_STEPS=3
fi
$NO_DATABASES    || TOTAL_STEPS=$((TOTAL_STEPS + 1))
$NO_APPS         || TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_OPENCLAW && TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_TUNNEL && TOTAL_STEPS=$((TOTAL_STEPS + 1))
STEP=0

#==============================================================================
# LOG
#==============================================================================
LOG_FILE="install.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=============================================================================="
echo "  INICIANDO INSTALACAO"
echo "  Data: $(date)"
if $APPS_ONLY; then
    echo "  Modo: Somente Apps (bancos + aplicacoes, sem Docker/Traefik/Portainer)"
elif $NO_DATABASES; then
    echo "  Modo: Somente Infraestrutura (Docker + Traefik + Portainer)"
elif $NO_APPS; then
    echo "  Modo: Infraestrutura + Bancos de Dados (sem aplicacoes)"
else
    echo "  Modo: Instalacao Completa"
fi
$INSTALL_OPENCLAW && echo "  Extra: OpenClaw (AI Assistant)"
$INSTALL_TUNNEL && echo "  Extra: Cloudflare Tunnel"
echo "=============================================================================="

#==============================================================================
# ETAPA: DOCKER E SWARM
#==============================================================================
if ! $APPS_ONLY; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Configurando Docker e Swarm..."
    bash 01-docker.sh
fi

#==============================================================================
# ETAPA: TRAEFIK
#==============================================================================
if ! $APPS_ONLY; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Deploy do Traefik..."
    bash 02-traefik.sh
fi

#==============================================================================
# ETAPA: PORTAINER
#==============================================================================
if ! $APPS_ONLY; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Deploy do Portainer..."
    bash 03-portainer.sh
fi

#==============================================================================
# AUTENTICACAO PORTAINER API (necessaria para deploy de stacks)
#==============================================================================
if ! $NO_DATABASES || $INSTALL_OPENCLAW; then
    source portainer_utils.sh
    check_deps
    authenticate "$PORTAINER_USER" "$PORTAINER_PASSWORD" || exit 1
fi

#==============================================================================
# ETAPA: BANCOS DE DADOS
#==============================================================================
if ! $NO_DATABASES; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Deploy dos Bancos de Dados..."

    echo "   > Redis..."
    deploy_stack "redis" "01-redis.yaml"

    echo "   > PostgreSQL..."
    envsubst < 02-postgres.yaml > /tmp/02-postgres_deploy.yaml
    deploy_stack "postgres" "/tmp/02-postgres_deploy.yaml"

    echo "   [INFO] Aguardando 30s para inicializacao do postgres..."
    sleep 30

    echo "   > MinIO..."
    envsubst < 03-minio.yaml > /tmp/03-minio_deploy.yaml
    deploy_stack "minio" "/tmp/03-minio_deploy.yaml"

    echo "   > MySQL..."
    envsubst < 11-mysql.yaml > /tmp/11-mysql_deploy.yaml
    deploy_stack "mysql" "/tmp/11-mysql_deploy.yaml"

    echo "   [INFO] Aguardando 60s para inicializacao do mysql..."
    sleep 60
fi

#==============================================================================
# ETAPA: APLICACOES
#==============================================================================
if ! $NO_APPS; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Deploy das Aplicacoes..."

    echo "   > n8n..."
    envsubst < 04-n8n/04-n8n-editor.yaml > /tmp/n8n-editor.yaml
    envsubst < 04-n8n/05-n8n-webhook.yaml > /tmp/n8n-webhook.yaml
    envsubst < 04-n8n/06-n8n-worker.yaml > /tmp/n8n-worker.yaml
    merge_yaml /tmp/n8n_full_deploy.yaml /tmp/n8n-editor.yaml /tmp/n8n-webhook.yaml /tmp/n8n-worker.yaml
    deploy_stack "n8n" "/tmp/n8n_full_deploy.yaml"

    echo "   > Chatwoot..."
    envsubst < chatwoot/07-chatwoot-admin.yaml > /tmp/chatwoot-admin.yaml
    envsubst < chatwoot/08-chatwoot-sidekiq.yaml > /tmp/chatwoot-sidekiq.yaml
    merge_yaml /tmp/chatwoot_full_deploy.yaml /tmp/chatwoot-admin.yaml /tmp/chatwoot-sidekiq.yaml
    deploy_stack "chatwoot" "/tmp/chatwoot_full_deploy.yaml"

    echo "   > Evolution API..."
    envsubst < 09-evolution.yaml > /tmp/evolution_deploy.yaml
    deploy_stack "evolution" "/tmp/evolution_deploy.yaml"

    echo "   > WordPress..."
    envsubst < 12-wordpress.yaml > /tmp/wordpress_deploy.yaml
    deploy_stack "wordpress" "/tmp/wordpress_deploy.yaml"
fi

#==============================================================================
# ETAPA: OPENCLAW (opcional)
#==============================================================================
if $INSTALL_OPENCLAW; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Deploy do OpenClaw (AI Assistant)..."

    envsubst < 10-openclaw.yaml > /tmp/openclaw_deploy.yaml
    deploy_stack "openclaw" "/tmp/openclaw_deploy.yaml"
fi

#==============================================================================
# ETAPA: CLOUDFLARE TUNNEL (opcional)
#==============================================================================
if $INSTALL_TUNNEL; then
    STEP=$((STEP + 1))
    echo
    echo ">>> [$STEP/$TOTAL_STEPS] Configurando Cloudflare Tunnel..."

    bash 04-cloudflared.sh
fi

#==============================================================================
# CONCLUSAO
#==============================================================================
echo
echo "=============================================================================="
echo "  INSTALACAO CONCLUIDA!"
if $APPS_ONLY; then
    echo "  Servicos instalados: Bancos de Dados + Aplicacoes"
elif $NO_DATABASES; then
    echo "  Servicos instalados: Docker, Traefik, Portainer"
elif $NO_APPS; then
    echo "  Servicos instalados: Docker, Traefik, Portainer + Bancos de Dados"
else
    echo "  Todos os servicos instalados"
fi
$INSTALL_OPENCLAW && echo "  + OpenClaw (AI Assistant)"
$INSTALL_TUNNEL && echo "  + Cloudflare Tunnel (Acesso Externo)"
echo "=============================================================================="
echo "Verifique os servicos com: docker service ls"
echo "Logs de instalacao salvos em: $LOG_FILE"
echo
