#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   install.sh
#  Funcao:   Instalacao Completa do Ambiente (All-in-One)
#  Versao:   1.0.0
#
#==============================================================================
[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

# Carrega Variaveis
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "[ERRO] Arquivo .env nao encontrado. Copie o .env.example e configure suas senhas."
    exit 1
fi

mkdir -p /storage/redis/{data,logs,config} && chown -R 999:1000 /storage/redis
mkdir -p /storage/postgres/{data,logs,config} && chown -R 999:999 /storage/postgres
mkdir -p /storage/minio/{data,logs,config} && chown -R 1000:1000 /storage/minio
mkdir -p /storage/n8n/{data,logs,config,nodes} && chown -R 1000:1000 /storage/n8n
mkdir -p /storage/chatwoot/{data,logs,config} && chown -R 1000:1000 /storage/chatwoot
mkdir -p /storage/evolution/{data,logs,config} && chown -R 1000:1000 /storage/evolution
mkdir -p /storage/mysql/{data,files,tmp} && chown -R 1001:1001 /storage/mysql
mkdir -p /storage/wordpress/data && chown -R 33:33 /storage/wordpress

LOG_FILE="install.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=============================================================================="
echo "  INICIANDO INSTALACAO COMPLETA"
echo "  Data: $(date)"
echo "=============================================================================="

# 1. Docker e Swarm
echo
echo ">>> [1/5] Configurando Docker e Swarm..."
bash 01-docker.sh

# 2. Infraestrutura de Rede (Traefik)
echo
echo ">>> [2/5] Deploy do Traefik..."
bash 02-traefik.sh

# 3. Gerenciamento (Portainer)
echo
echo ">>> [3/5] Deploy do Portainer..."
bash 03-portainer.sh

# 5. Aplicacoes
echo
echo ">>> [5/5] Deploy da Infraestrutura e Aplicacoes via Portainer API..."

# Load Portainer Utils
source portainer_utils.sh
check_deps
authenticate "$PORTAINER_USER" "$PORTAINER_PASSWORD" || exit 1

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

echo "   > n8n..."
# Concatenating n8n files for single stack deployment in Portainer
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

echo "   > MySQL..."
envsubst < 11-mysql.yaml > /tmp/11-mysql_deploy.yaml
deploy_stack "mysql" "/tmp/11-mysql_deploy.yaml"

echo "   [INFO] Aguardando 60s para inicializacao do mysql..."
sleep 60

echo "   > WordPress..."
envsubst < 12-wordpress.yaml > /tmp/wordpress_deploy.yaml
deploy_stack "wordpress" "/tmp/wordpress_deploy.yaml"

echo
echo "=============================================================================="
echo "  INSTALACAO CONCLUIDA!"
echo "=============================================================================="
echo "Verifique os servicos com: docker service ls"
echo "Logs de instalacao salvos em: $LOG_FILE"
echo
