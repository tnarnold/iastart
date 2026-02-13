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
#    bash install.sh --no-apps       # Sem aplicacoes (somente infra + bancos)
#    bash install.sh --no-databases  # Somente Docker + Traefik + Portainer
#    bash install.sh --openclaw      # Instalacao completa + OpenClaw
#
#==============================================================================

#==============================================================================
# PARSE DE ARGUMENTOS
#==============================================================================
NO_APPS=false
NO_DATABASES=false
INSTALL_OPENCLAW=false

show_help() {
    echo "Uso: bash install.sh [OPCOES]"
    echo ""
    echo "OPCOES:"
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
    echo "  -h, --help        Exibe esta ajuda"
    echo ""
    echo "Sem opcoes: instalacao completa de todos os servicos (sem OpenClaw)."
}

for arg in "$@"; do
    case $arg in
        --no-apps)      NO_APPS=true ;;
        --no-databases) NO_DATABASES=true; NO_APPS=true ;;
        --openclaw)     INSTALL_OPENCLAW=true ;;
        -h|--help)      show_help; exit 0 ;;
        *)              echo "[ERRO] Parametro desconhecido: $arg"; show_help; exit 1 ;;
    esac
done

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
TOTAL_STEPS=3
$NO_DATABASES    || TOTAL_STEPS=$((TOTAL_STEPS + 1))
$NO_APPS         || TOTAL_STEPS=$((TOTAL_STEPS + 1))
$INSTALL_OPENCLAW && TOTAL_STEPS=$((TOTAL_STEPS + 1))
STEP=0

#==============================================================================
# LOG
#==============================================================================
LOG_FILE="install.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=============================================================================="
echo "  INICIANDO INSTALACAO"
echo "  Data: $(date)"
if $NO_DATABASES; then
    echo "  Modo: Somente Infraestrutura (Docker + Traefik + Portainer)"
elif $NO_APPS; then
    echo "  Modo: Infraestrutura + Bancos de Dados (sem aplicacoes)"
else
    echo "  Modo: Instalacao Completa"
fi
$INSTALL_OPENCLAW && echo "  Extra: OpenClaw (AI Assistant)"
echo "=============================================================================="

#==============================================================================
# ETAPA: DOCKER E SWARM
#==============================================================================
STEP=$((STEP + 1))
echo
echo ">>> [$STEP/$TOTAL_STEPS] Configurando Docker e Swarm..."
bash 01-docker.sh

#==============================================================================
# ETAPA: TRAEFIK
#==============================================================================
STEP=$((STEP + 1))
echo
echo ">>> [$STEP/$TOTAL_STEPS] Deploy do Traefik..."
bash 02-traefik.sh

#==============================================================================
# ETAPA: PORTAINER
#==============================================================================
STEP=$((STEP + 1))
echo
echo ">>> [$STEP/$TOTAL_STEPS] Deploy do Portainer..."
bash 03-portainer.sh

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
    {
      cat /tmp/n8n-editor.yaml
      echo -e "\n---\n"
      cat /tmp/n8n-webhook.yaml
      echo -e "\n---\n"
      cat /tmp/n8n-worker.yaml
    } > /tmp/n8n_full_deploy.yaml
    deploy_stack "n8n" "/tmp/n8n_full_deploy.yaml"

    echo "   > Chatwoot..."
    envsubst < chatwoot/07-chatwoot-admin.yaml > /tmp/chatwoot-admin.yaml
    envsubst < chatwoot/08-chatwoot-sidekiq.yaml > /tmp/chatwoot-sidekiq.yaml
    {
      cat /tmp/chatwoot-admin.yaml
      echo -e "\n---\n"
      cat /tmp/chatwoot-sidekiq.yaml
    } > /tmp/chatwoot_full_deploy.yaml
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
# CONCLUSAO
#==============================================================================
echo
echo "=============================================================================="
echo "  INSTALACAO CONCLUIDA!"
if $NO_DATABASES; then
    echo "  Servicos instalados: Docker, Traefik, Portainer"
elif $NO_APPS; then
    echo "  Servicos instalados: Docker, Traefik, Portainer + Bancos de Dados"
else
    echo "  Todos os servicos instalados"
fi
$INSTALL_OPENCLAW && echo "  + OpenClaw (AI Assistant)"
echo "=============================================================================="
echo "Verifique os servicos com: docker service ls"
echo "Logs de instalacao salvos em: $LOG_FILE"
echo
