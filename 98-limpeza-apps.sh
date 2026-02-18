#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   98-limpeza-apps.sh
#  Funcao:   Remove apps e bancos, mantendo Docker/Swarm/Traefik/Portainer
#  Versao:   1.0.0
#
#  MANTÉM:
#    - Docker + Docker Swarm
#    - Traefik (reverse proxy + certificados SSL)
#    - Portainer (gerenciamento)
#    - Rede network_public
#
#  REMOVE:
#    - Stacks: redis, postgres, mysql, minio, n8n, chatwoot, evolution,
#              wordpress, openclaw
#    - Dados: /storage/{redis,postgres,mysql,minio,n8n,chatwoot,evolution,
#             wordpress,openclaw}
#
#  USO:
#    bash 98-limpeza-apps.sh              # Remove apps e bancos
#    bash 98-limpeza-apps.sh --tunnel     # Remove apps, bancos E tunnel
#
#==============================================================================

[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

#==============================================================================
# CONFIGURACAO
#==============================================================================

# Stacks que serao REMOVIDAS
STACKS_REMOVER=(
    "redis"
    "postgres"
    "mysql"
    "minio"
    "n8n"
    "chatwoot"
    "evolution"
    "wordpress"
    "openclaw"
)

# Dados que serao REMOVIDOS
STORAGE_REMOVER=(
    "/storage/redis"
    "/storage/postgres"
    "/storage/mysql"
    "/storage/minio"
    "/storage/n8n"
    "/storage/chatwoot"
    "/storage/evolution"
    "/storage/wordpress"
    "/storage/openclaw"
)

# Stacks que serao MANTIDAS (apenas informativo)
STACKS_MANTER=("traefik" "portainer")

#==============================================================================
# FUNCOES
#==============================================================================
log_info()    { echo "[INFO]  $1"; }
log_success() { echo "[OK]    $1"; }
log_warn()    { echo "[AVISO] $1"; }

#==============================================================================
# CONFIRMACAO
#==============================================================================
echo
echo "=============================================================================="
echo "  LIMPEZA DE APPS E BANCOS DE DADOS"
echo "=============================================================================="
echo
echo "  Sera REMOVIDO:"
for stack in "${STACKS_REMOVER[@]}"; do
    echo "    - Stack: $stack"
done
if [ "$1" = "--tunnel" ]; then
    echo "    - Stack: cloudflared"
    echo "    - Cloudflare Tunnel (API)"
fi
echo
echo "  Dados que serao APAGADOS:"
for path in "${STORAGE_REMOVER[@]}"; do
    if [ -d "$path" ]; then
        SIZE=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
        echo "    - $path ($SIZE)"
    fi
done
if [ "$1" = "--tunnel" ]; then
    [ -d "/storage/cloudflared" ] && echo "    - /storage/cloudflared"
fi
echo
echo "  Sera MANTIDO:"
for stack in "${STACKS_MANTER[@]}"; do
    echo "    - Stack: $stack"
done
echo "    - Docker + Swarm"
echo "    - Rede network_public"
echo "    - /storage/traefik (certificados SSL)"
echo "    - /storage/portainer"
echo

read -p "Continuar? (s/N): " R
[[ ! "$R" =~ ^[Ss]$ ]] && { echo "Cancelado."; exit 0; }

read -p "Digite LIMPAR para confirmar: " C
[ "$C" != "LIMPAR" ] && { echo "Cancelado."; exit 0; }

echo

#==============================================================================
# ETAPA 1: REMOVER TUNNEL (se --tunnel)
#==============================================================================
if [ "$1" = "--tunnel" ]; then
    echo "[1/4] Removendo Cloudflare Tunnel..."
    if [ -f "04-cloudflared.sh" ]; then
        bash 04-cloudflared.sh --delete
    else
        # Remove stack manualmente
        docker stack rm cloudflared 2>/dev/null
        log_warn "04-cloudflared.sh nao encontrado. Stack removida mas tunnel pode existir na Cloudflare."
    fi
    sleep 3
else
    echo "[1/4] Tunnel: pulando (use --tunnel para remover)"
    # Remove apenas a stack local do cloudflared (sem deletar o tunnel na Cloudflare)
    if docker stack ls 2>/dev/null | grep -q "cloudflared"; then
        docker stack rm cloudflared 2>/dev/null
        log_info "Stack cloudflared removida (tunnel continua na Cloudflare)"
        sleep 3
    fi
fi

#==============================================================================
# ETAPA 2: REMOVER STACKS DE APPS
#==============================================================================
echo "[2/4] Removendo stacks de apps..."
for stack in "${STACKS_REMOVER[@]}"; do
    if docker stack ls 2>/dev/null | grep -q "$stack"; then
        docker stack rm "$stack" 2>/dev/null
        log_success "Stack removida: $stack"
    else
        log_info "Stack nao encontrada: $stack (pulando)"
    fi
done

# Aguarda containers pararem
log_info "Aguardando containers pararem..."
sleep 10

#==============================================================================
# ETAPA 3: LIMPAR CONTAINERS ORFAOS
#==============================================================================
echo "[3/4] Limpando containers orfaos e imagens nao utilizadas..."

# Remove containers parados (exceto traefik e portainer)
for cid in $(docker ps -aq --filter "status=exited" 2>/dev/null); do
    NAME=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null)
    if [[ ! "$NAME" =~ traefik|portainer ]]; then
        docker rm -f "$cid" 2>/dev/null
    fi
done

# Limpa imagens nao utilizadas
docker image prune -af 2>/dev/null
log_success "Containers e imagens limpos"

#==============================================================================
# ETAPA 4: REMOVER DADOS
#==============================================================================
echo "[4/4] Removendo dados..."
for path in "${STORAGE_REMOVER[@]}"; do
    if [ -d "$path" ]; then
        rm -rf "$path"
        log_success "Removido: $path"
    fi
done

if [ "$1" = "--tunnel" ] && [ -d "/storage/cloudflared" ]; then
    rm -rf /storage/cloudflared
    log_success "Removido: /storage/cloudflared"
fi

#==============================================================================
# VERIFICACAO
#==============================================================================
echo
echo "=============================================================================="
echo "  LIMPEZA CONCLUIDA"
echo "=============================================================================="
echo
echo "  Stacks ativas:"
docker stack ls 2>/dev/null | grep -v "^NAME" | while read -r line; do
    echo "    - $line"
done
echo
echo "  Para reinstalar as apps:"
echo "    bash install.sh"
echo
