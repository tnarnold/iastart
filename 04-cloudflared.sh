#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   04-cloudflared.sh
#  Funcao:   Criacao automatica de Cloudflare Tunnel + Deploy do cloudflared
#  Versao:   1.0.0
#
#  DEPENDENCIAS: 01-docker.sh, 02-traefik.sh
#
#  VARIAVEIS NECESSARIAS NO .env:
#    - CF_ACCOUNT_ID       (ID da conta Cloudflare)
#    - CF_TUNNEL_API_TOKEN  (API token com permissao Tunnel:Edit + DNS:Edit)
#    - CF_ZONE_ID           (Zone ID do dominio - encontre no dashboard Cloudflare)
#    - DOMAIN              (dominio principal)
#
#  USO:
#    bash 04-cloudflared.sh              # Cria tunnel e faz deploy
#    bash 04-cloudflared.sh --delete     # Remove tunnel e stack
#
#==============================================================================
[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

#==============================================================================
# CARREGAMENTO DE VARIAVEIS (.env)
#==============================================================================
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "[ERRO] Arquivo .env nao encontrado."
    exit 1
fi

#==============================================================================
# FUNCOES
#==============================================================================
log_info()    { echo "[INFO]  $1"; }
log_success() { echo "[OK]    $1"; }
log_warn()    { echo "[AVISO] $1"; }
log_error()   { echo "[ERRO]  $1"; }

CF_API="https://api.cloudflare.com/client/v4"
TUNNEL_NAME="iastart-${DOMAIN}"

cf_api() {
    local method=$1 endpoint=$2 data=$3
    local args=(-s -X "$method" "${CF_API}${endpoint}" \
        -H "Authorization: Bearer ${CF_TUNNEL_API_TOKEN}" \
        -H "Content-Type: application/json")
    [ -n "$data" ] && args+=(-d "$data")
    curl "${args[@]}"
}

# Usa CF_DNS_API_TOKEN para operacoes de DNS (token separado com permissao DNS:Edit)
cf_dns_api() {
    local method=$1 endpoint=$2 data=$3
    local token="${CF_DNS_API_TOKEN:-$CF_TUNNEL_API_TOKEN}"
    local args=(-s -X "$method" "${CF_API}${endpoint}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")
    [ -n "$data" ] && args+=(-d "$data")
    curl "${args[@]}"
}

#==============================================================================
# VALIDACOES
#==============================================================================
echo
echo "=============================================================================="
echo "  Cloudflare Tunnel - Setup Automatico"
echo "=============================================================================="
echo

# Dependencias
if ! command -v curl &>/dev/null; then
    log_info "Instalando curl e jq..."
    apt-get update -qq && apt-get install -y -qq curl jq
fi
if ! command -v jq &>/dev/null; then
    log_info "Instalando jq..."
    apt-get update -qq && apt-get install -y -qq jq
fi

# Variaveis obrigatorias
[ -z "$CF_ACCOUNT_ID" ] && { log_error "CF_ACCOUNT_ID nao definido no .env"; exit 1; }
[ -z "$CF_TUNNEL_API_TOKEN" ] && { log_error "CF_TUNNEL_API_TOKEN nao definido no .env"; exit 1; }
[ -z "$CF_ZONE_ID" ] && { log_error "CF_ZONE_ID nao definido no .env. Encontre em: Cloudflare Dashboard > Dominio > Visao Geral (lado direito)"; exit 1; }
[ -z "$DOMAIN" ] && { log_error "DOMAIN nao definido no .env"; exit 1; }

# Docker e Swarm
docker info > /dev/null 2>&1 || { log_error "Docker nao esta rodando"; exit 1; }
docker info 2>/dev/null | grep -q "Swarm: active" || { log_error "Docker Swarm nao ativo"; exit 1; }
docker network ls | grep -q "network_public" || { log_error "Rede network_public nao existe"; exit 1; }

# Testa autenticacao na API
log_info "Testando autenticacao na API Cloudflare..."
AUTH_TEST=$(cf_api GET "/user/tokens/verify")
if ! echo "$AUTH_TEST" | jq -r '.success' | grep -q true; then
    log_error "Token da API Cloudflare invalido ou sem permissao"
    echo "$AUTH_TEST" | jq '.errors'
    exit 1
fi
log_success "Autenticacao OK"

#==============================================================================
# DELETE MODE
#==============================================================================
if [ "$1" = "--delete" ]; then
    log_info "Modo de remocao..."

    # Busca tunnel existente
    EXISTING=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false")
    TUNNEL_ID=$(echo "$EXISTING" | jq -r '.result[0].id // empty')

    if [ -n "$TUNNEL_ID" ]; then
        # Remove stack primeiro
        if docker stack ls | grep -q "cloudflared"; then
            log_info "Removendo stack cloudflared..."
            docker stack rm cloudflared
            sleep 5
        fi

        # Remove DNS records
        log_info "Removendo registros DNS do tunnel..."
        ZONE_ID="$CF_ZONE_ID"
        if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "null" ]; then
            TUNNEL_CNAMES=$(cf_dns_api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&content=${TUNNEL_ID}.cfargotunnel.com&per_page=50")
            echo "$TUNNEL_CNAMES" | jq -r '.result[].id' | while read -r RECORD_ID; do
                cf_dns_api DELETE "/zones/${ZONE_ID}/dns_records/${RECORD_ID}" > /dev/null
            done
            log_success "DNS records removidos"
        fi

        # Limpa conexoes e deleta tunnel
        log_info "Limpando conexoes do tunnel..."
        cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/connections" > /dev/null
        sleep 2

        log_info "Deletando tunnel..."
        DELETE_RESULT=$(cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}")
        if echo "$DELETE_RESULT" | jq -r '.success' | grep -q true; then
            log_success "Tunnel removido com sucesso"
        else
            log_error "Falha ao remover tunnel"
            echo "$DELETE_RESULT" | jq '.errors'
        fi

        # Remove token do .env
        if grep -q "CLOUDFLARE_TUNNEL_TOKEN=" .env; then
            sed -i '/CLOUDFLARE_TUNNEL_TOKEN=/d' .env
            log_success "Token removido do .env"
        fi
    else
        log_warn "Nenhum tunnel encontrado com nome: $TUNNEL_NAME"
    fi
    exit 0
fi

#==============================================================================
# ETAPA 1: VERIFICAR/CRIAR TUNNEL
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 1/4: Criando Tunnel"
echo "=============================================================================="
echo

# Verifica se tunnel ja existe
EXISTING=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false")
TUNNEL_ID=$(echo "$EXISTING" | jq -r '.result[0].id // empty')

if [ -n "$TUNNEL_ID" ]; then
    log_info "Tunnel ja existe: $TUNNEL_NAME (ID: $TUNNEL_ID)"
else
    log_info "Criando tunnel: $TUNNEL_NAME"

    # Gera secret para o tunnel
    TUNNEL_SECRET=$(openssl rand -base64 32)

    CREATE_RESULT=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
        "{\"name\":\"${TUNNEL_NAME}\",\"tunnel_secret\":\"${TUNNEL_SECRET}\",\"config_src\":\"cloudflare\"}")

    if echo "$CREATE_RESULT" | jq -r '.success' | grep -q true; then
        TUNNEL_ID=$(echo "$CREATE_RESULT" | jq -r '.result.id')
        log_success "Tunnel criado: $TUNNEL_ID"
    else
        log_error "Falha ao criar tunnel"
        echo "$CREATE_RESULT" | jq '.errors'
        exit 1
    fi
fi

#==============================================================================
# ETAPA 2: CONFIGURAR ROTEAMENTO DO TUNNEL
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 2/4: Configurando roteamento"
echo "=============================================================================="
echo

# Lista de subdomínios a configurar
# Cada entrada: subdominio:servico:porta:protocolo
SUBDOMAINS=(
    "wf:traefik:443"
    "wb:traefik:443"
    "app:traefik:443"
    "ws:traefik:443"
    "chat:traefik:443"
    "s3:traefik:443"
    "cdn:traefik:443"
    "pn:traefik:443"
)

# Adiciona OpenClaw se instalado
if $INSTALL_OPENCLAW 2>/dev/null || docker service ls 2>/dev/null | grep -q openclaw; then
    SUBDOMAINS+=("ai:traefik:443")
fi

# Monta ingress rules (noTLSVerify para aceitar cert interno do Traefik)
INGRESS_RULES="["
for entry in "${SUBDOMAINS[@]}"; do
    IFS=':' read -r sub service port <<< "$entry"
    hostname="${sub}.${DOMAIN}"
    INGRESS_RULES+="{\"hostname\":\"${hostname}\",\"service\":\"https://${service}:${port}\",\"originRequest\":{\"noTLSVerify\":true}},"
done
# Catch-all rule (obrigatório)
INGRESS_RULES+="{\"service\":\"http_status:404\"}"
INGRESS_RULES+="]"

CONFIG_PAYLOAD="{\"config\":{\"ingress\":${INGRESS_RULES}}}"

log_info "Aplicando configuracao de ingress..."
CONFIG_RESULT=$(cf_api PUT "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "$CONFIG_PAYLOAD")

if echo "$CONFIG_RESULT" | jq -r '.success' | grep -q true; then
    log_success "Roteamento configurado"
    for entry in "${SUBDOMAINS[@]}"; do
        IFS=':' read -r sub service port <<< "$entry"
        echo "         ${sub}.${DOMAIN} -> https://${service}:${port}"
    done
else
    log_error "Falha ao configurar roteamento"
    echo "$CONFIG_RESULT" | jq '.errors'
    exit 1
fi

#==============================================================================
# ETAPA 3: CRIAR DNS RECORDS (CNAME -> tunnel)
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 3/4: Criando registros DNS"
echo "=============================================================================="
echo

# Usa CF_ZONE_ID do .env
ZONE_ID="$CF_ZONE_ID"

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
    log_error "CF_ZONE_ID nao definido no .env"
    log_warn "Crie os registros CNAME manualmente apontando para: ${TUNNEL_ID}.cfargotunnel.com"
else
    log_info "Zone ID: $ZONE_ID"

    for entry in "${SUBDOMAINS[@]}"; do
        IFS=':' read -r sub service port <<< "$entry"
        FULL_HOST="${sub}.${DOMAIN}"

        # Verifica se registro ja existe
        EXISTING_DNS=$(cf_dns_api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&name=${FULL_HOST}")
        EXISTING_ID=$(echo "$EXISTING_DNS" | jq -r '.result[0].id // empty')

        if [ -n "$EXISTING_ID" ]; then
            # Atualiza registro existente
            DNS_RESULT=$(cf_dns_api PUT "/zones/${ZONE_ID}/dns_records/${EXISTING_ID}" \
                "{\"type\":\"CNAME\",\"name\":\"${sub}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}")
            ACTION="atualizado"
        else
            # Cria novo registro
            DNS_RESULT=$(cf_dns_api POST "/zones/${ZONE_ID}/dns_records" \
                "{\"type\":\"CNAME\",\"name\":\"${sub}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}")
            ACTION="criado"
        fi

        if echo "$DNS_RESULT" | jq -r '.success' | grep -q true; then
            log_success "DNS ${ACTION}: ${FULL_HOST} -> tunnel"
        else
            log_warn "Falha no DNS para ${FULL_HOST}"
            echo "$DNS_RESULT" | jq '.errors'
        fi
    done
fi

#==============================================================================
# ETAPA 4: OBTER TOKEN E DEPLOY
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 4/4: Deploy do cloudflared"
echo "=============================================================================="
echo

# Obtém o token do tunnel
log_info "Obtendo token do tunnel..."
TOKEN_RESULT=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token")

if echo "$TOKEN_RESULT" | jq -r '.success' | grep -q true; then
    TUNNEL_TOKEN=$(echo "$TOKEN_RESULT" | jq -r '.result')
    log_success "Token obtido"
else
    log_error "Falha ao obter token do tunnel"
    echo "$TOKEN_RESULT" | jq '.errors'
    exit 1
fi

# Salva token no .env
if grep -q "CLOUDFLARE_TUNNEL_TOKEN=" .env; then
    sed -i "s|CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=${TUNNEL_TOKEN}|" .env
    log_info "Token atualizado no .env"
else
    echo "" >> .env
    echo "# Cloudflare Tunnel (gerado automaticamente por 04-cloudflared.sh)" >> .env
    echo "CLOUDFLARE_TUNNEL_TOKEN=${TUNNEL_TOKEN}" >> .env
    log_success "Token adicionado ao .env"
fi

# Exporta token para o envsubst
export CLOUDFLARE_TUNNEL_TOKEN="$TUNNEL_TOKEN"

# Deploy da stack
log_info "Fazendo deploy do cloudflared..."

# Remove stack anterior se existir
if docker stack ls | grep -q "cloudflared"; then
    docker stack rm cloudflared
    sleep 5
fi

envsubst < 13-cloudflared.yaml > /tmp/13-cloudflared_deploy.yaml
docker stack deploy -c /tmp/13-cloudflared_deploy.yaml cloudflared

# Aguarda o serviço subir
log_info "Aguardando servico iniciar..."
for i in $(seq 1 30); do
    if docker service ls | grep cloudflared_cloudflared | grep -q "1/1"; then
        break
    fi
    sleep 2
    echo -n "."
done
echo

# Verifica status
if docker service ls | grep cloudflared_cloudflared | grep -q "1/1"; then
    log_success "cloudflared rodando"
else
    log_warn "cloudflared ainda nao esta 1/1, verifique com: docker service logs cloudflared_cloudflared"
fi

#==============================================================================
# CONCLUSAO
#==============================================================================
echo
echo "=============================================================================="
echo "  CLOUDFLARE TUNNEL - CONFIGURADO!"
echo "=============================================================================="
echo
echo "  Tunnel:    $TUNNEL_NAME"
echo "  Tunnel ID: $TUNNEL_ID"
echo
echo "  Subdomínios configurados:"
for entry in "${SUBDOMAINS[@]}"; do
    IFS=':' read -r sub service port <<< "$entry"
    echo "    https://${sub}.${DOMAIN}"
done
echo
echo "  Comandos uteis:"
echo "    docker service logs cloudflared_cloudflared    # Ver logs"
echo "    bash 04-cloudflared.sh --delete                # Remover tunnel"
echo
