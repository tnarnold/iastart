#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   03-portainer.sh
#  Funcao:   Deploy do Portainer + criacao de admin
#  Versao:   3.2.0
#
#  DEPENDENCIAS: 01-docker.sh, 02-traefik.sh
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
fi
#==============================================================================
# FUNCOES
#==============================================================================
log_info()    { echo "[INFO]  $1"; }
log_success() { echo "[OK]    $1"; }
log_warn()    { echo "[AVISO] $1"; }
log_error()   { echo "[ERRO]  $1"; }
wait_for() {
    local description=$1 check_cmd=$2 timeout=${3:-120} interval=${4:-3} elapsed=0
    log_info "Aguardando: $description (timeout: ${timeout}s)"
    while [ $elapsed -lt $timeout ]; do
        if eval "$check_cmd" > /dev/null 2>&1; then
            log_success "$description"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    echo
    log_error "Timeout aguardando: $description"
    return 1
}
#==============================================================================
# ETAPA 1: DEPENDENCIAS
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 1/5: Dependencias"
echo "=============================================================================="
echo
if ! command -v curl &>/dev/null; then
    log_info "Instalando curl..."
    apt-get update -qq && apt-get install -y -qq curl
fi
log_success "curl OK"
#==============================================================================
# ETAPA 2: VERIFICACOES
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 2/5: Verificacoes"
echo "=============================================================================="
echo
docker info > /dev/null 2>&1 || { log_error "Docker nao esta rodando"; exit 1; }
log_success "Docker OK"
docker info 2>/dev/null | grep -q "Swarm: active" || { log_error "Docker Swarm nao ativo"; exit 1; }
log_success "Swarm OK"
docker network ls | grep -q "network_public" || { log_error "Rede network_public nao existe"; exit 1; }
log_success "Rede OK"
#==============================================================================
# ETAPA 3: CONFIGURACOES
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 3/5: Configuracoes"
echo "=============================================================================="
echo
DOMAIN="${DOMAIN:-$(hostname -f)}"
SERVER_IP=$(hostname -I | awk '{print $1}')
PORTAINER_USER="${PORTAINER_USER:-admin}"
PORTAINER_PASS="${PORTAINER_PASSWORD}"
log_success "DOMAIN: $DOMAIN"
log_success "SERVER_IP: $SERVER_IP"
log_success "Usuario: $PORTAINER_USER"
log_success "Senha: $PORTAINER_PASS"
#==============================================================================
# ETAPA 4: DEPLOY PORTAINER
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 4/5: Deploy do Portainer"
echo "=============================================================================="
echo
mkdir -p /storage/portainer/{data,logs,config}
# Limpa instalacao anterior se existir
if [ -f "/storage/portainer/data/portainer.db" ]; then
    log_warn "Instalacao anterior detectada"
    echo -n "Limpar e reinstalar? (s/N): "
    read -r LIMPAR
    if [[ "$LIMPAR" =~ ^[Ss]$ ]]; then
        rm -rf /storage/portainer/data/*
        log_success "Dados limpos"
    fi
fi
# Remove stack anterior
if docker stack ls | grep -q "portainer"; then
    log_info "Removendo stack anterior..."
    docker stack rm portainer
    wait_for "Stack removida" "! docker stack ls | grep -q portainer" 60 2
    sleep 5
fi
# Cria YAML
cat > /storage/portainer/config/portainer.yaml << YAML
services:
  portainer:
    image: portainer/portainer-ce:lts
    hostname: portainer.intranet.br
    environment:
      - TZ=America/Sao_Paulo
    ports:
      - 9000:9000
      - 9443:9443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /storage/portainer/data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M
      labels:
        - traefik.enable=true
        - traefik.docker.network=network_public
        - traefik.http.routers.portainer.rule=Host(\`pn.${DOMAIN}\`)
        - traefik.http.routers.portainer.entrypoints=websecure
        - traefik.http.routers.portainer.tls.certresolver=letsencrypt
        - traefik.http.services.portainer.loadbalancer.server.port=9000
networks:
  network_public:
    external: true
YAML
log_success "YAML criado"
# Deploy
log_info "Executando deploy..."
docker stack deploy -c /storage/portainer/config/portainer.yaml portainer
wait_for "Stack criada" "docker stack ls | grep -q portainer" 30 2
wait_for "Servico running" "docker service ls | grep portainer_portainer | grep -q '1/1'" 120 3
log_success "Portainer deployado"
#==============================================================================
# ETAPA 5: CRIAR ADMIN
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 5/5: Criando Usuario Admin"
echo "=============================================================================="
echo
PORTAINER_URL="https://127.0.0.1:9443"
# Aguarda API estar disponivel
wait_for "API disponivel" "curl -sk ${PORTAINER_URL}/api/status | grep -q Version" 180 3
# Aguarda banco estar pronto (verifica se endpoint de admin responde corretamente)
log_info "Aguardando banco inicializar..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${PORTAINER_URL}/api/users/admin/check")
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "404" ]; then
        log_success "Banco pronto"
        break
    fi
    sleep 2
done
# Verifica se admin ja existe (204 = existe, 404 = nao existe)
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${PORTAINER_URL}/api/users/admin/check")
if [ "$HTTP_CODE" = "204" ]; then
    log_info "Usuario admin ja existe"
else
    log_info "Criando usuario admin..."
    
    # Tenta criar admin
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "${PORTAINER_URL}/api/users/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"${PORTAINER_USER}\",\"Password\":\"${PORTAINER_PASS}\"}")
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        log_success "Usuario admin criado"
    elif [ "$HTTP_CODE" = "409" ]; then
        log_info "Usuario admin ja existe"
    else
        log_warn "Falha ao criar admin (HTTP $HTTP_CODE). Crie manualmente em: https://${SERVER_IP}:9443"
    fi
fi
echo
echo "[OK] Portainer deployed"
echo
echo "Acesso: https://${SERVER_IP}:9443"
echo "Usuario: ${PORTAINER_USER}"
echo "Senha: ${PORTAINER_PASS}"
echo