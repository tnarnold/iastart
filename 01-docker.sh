#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   01-docker.sh
#  Funcao:   Instala Docker e configura Swarm
#  Versao:   2.0.0
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
    echo "[INFO] Variaveis de ambiente carregadas do .env"
else
    echo "[AVISO] Arquivo .env nao encontrado! Usando valores padrao ou hardcoded pode falhar."
fi

#==============================================================================
# FUNCOES
#==============================================================================
get_ip() { 
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $7}'
}
docker_clean() {
    echo "[INFO] Limpando ambiente Docker..."
    for stack in $(docker stack ls --format '{{.Name}}' 2>/dev/null); do 
        docker stack rm "$stack" 2>/dev/null
    done
    sleep 5
    docker service rm $(docker service ls -q 2>/dev/null) 2>/dev/null
    sleep 3
    docker stop $(docker ps -aq 2>/dev/null) 2>/dev/null
    docker rm -f $(docker ps -aq 2>/dev/null) 2>/dev/null
    docker swarm leave --force 2>/dev/null
    sleep 2
    for net in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$'); do 
        docker network rm "$net" 2>/dev/null
    done
    docker rmi -f $(docker images -aq 2>/dev/null) 2>/dev/null
    docker system prune -af 2>/dev/null
    docker network prune -f 2>/dev/null
    echo "[OK] Ambiente limpo"
}
#==============================================================================
# INSTALACAO DO DOCKER
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 1/2: Instalacao do Docker"
echo "=============================================================================="
echo
if ! command -v docker &>/dev/null; then
    echo "[INFO] Instalando Docker..."
    apt-get update && apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker && systemctl start docker
    echo "[OK] Docker instalado"
else
    echo "[OK] Docker ja instalado: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi
#==============================================================================
# CONFIGURACAO DO SWARM
#==============================================================================
echo
echo "=============================================================================="
echo "  ETAPA 2/2: Configuracao do Docker Swarm"
echo "=============================================================================="
echo
SERVER_IP=$(get_ip)
[ -z "$SERVER_IP" ] && { read -p "IP do servidor: " SERVER_IP; [ -z "$SERVER_IP" ] && exit 1; }
echo "[OK] IP do servidor: $SERVER_IP"
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "[AVISO] Swarm ja ativo. Recriar vai apagar containers, imagens e networks (volumes mantidos)."
    echo -n "Recriar do zero? (s/N): "
    read -r R
    if [[ "$R" =~ ^[Ss]$ ]]; then
        echo -n "Digite CONFIRMAR para prosseguir: "
        read -r C
        [ "$C" = "CONFIRMAR" ] && docker_clean || { echo "Cancelado."; exit 0; }
    else
        echo "[OK] Swarm mantido sem alteracoes"
    fi
fi
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    docker swarm init --advertise-addr="$SERVER_IP" || exit 1
    echo "[OK] Swarm inicializado"
fi
# Cria rede overlay
if ! docker network ls --format '{{.Name}}' | grep -q "^network_public$"; then
    docker network create --driver=overlay network_public
    echo "[OK] Rede network_public criada"
else
    echo "[OK] Rede network_public ja existe"
fi
echo
echo "[OK] Docker Swarm configurado"
echo
echo "IP: ${SERVER_IP}"
echo "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
echo
echo "Proximo: bash 02-traefik.sh"
echo