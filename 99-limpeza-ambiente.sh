#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   99-limpeza-ambiente.sh
#  Funcao:   Remove completamente Docker, Swarm e dados
#  Versao:   1.0.0
#
#  ATENCAO: Este script APAGA TODOS os dados do ambiente!
#
#  PASSO A PASSO:
#    1. Copiar todo o conteudo deste script
#    2. Acessar o servidor via SSH: ssh root@IP_DO_SERVIDOR
#    3. Colar no terminal e pressionar Enter
#
#==============================================================================

[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

echo "LIMPEZA TOTAL DO AMBIENTE"
echo "========================="
echo
echo "Sera removido:"
echo "  - Stacks, servicos, containers"
echo "  - Imagens, volumes, networks"
echo "  - Docker Swarm"
echo "  - /storage/"
echo
echo "ATENCAO: Dados serao perdidos permanentemente."
echo

read -p "Continuar? (s/N): " R
[[ ! "$R" =~ ^[Ss]$ ]] && { echo "Cancelado."; exit 0; }

read -p "Digite APAGAR para confirmar: " C
[ "$C" != "APAGAR" ] && { echo "Cancelado."; exit 0; }

echo
echo "[1/7] Removendo stacks..."
for stack in $(docker stack ls --format '{{.Name}}' 2>/dev/null); do
    docker stack rm "$stack" 2>/dev/null
done
sleep 5

echo "[2/7] Removendo servicos..."
docker service rm $(docker service ls -q 2>/dev/null) 2>/dev/null
sleep 3

echo "[3/7] Parando e removendo containers..."
docker stop $(docker ps -aq 2>/dev/null) 2>/dev/null
docker rm -f $(docker ps -aq 2>/dev/null) 2>/dev/null

echo "[4/7] Saindo do Swarm..."
docker swarm leave --force 2>/dev/null
sleep 2

echo "[5/7] Removendo networks..."
for net in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$'); do
    docker network rm "$net" 2>/dev/null
done

echo "[6/7] Removendo imagens, volumes e cache..."
docker rmi -f $(docker images -aq 2>/dev/null) 2>/dev/null
docker volume rm -f $(docker volume ls -q 2>/dev/null) 2>/dev/null
docker system prune -af --volumes 2>/dev/null
docker network prune -f 2>/dev/null
docker volume prune -af 2>/dev/null
docker builder prune -af 2>/dev/null

echo "[7/7] Removendo /storage/..."
rm -rf /storage 2>/dev/null

echo
echo "[OK] Ambiente limpo"
echo
