#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   02-traefik.sh
#  Funcao:   Deploy do Traefik (Reverse Proxy + SSL)
#  Versao:   1.0.0
#
#  DEPENDENCIAS: 01-docker.sh
#
#==============================================================================
EMAIL="${SMTP_FROM_EMAIL}"
# Estrutura de diretórios
mkdir -p /storage/traefik/{data,logs,config}

# Verifica se existe backup de certificados no repositorio
if [ -f "certs/acme.json" ]; then
    echo "[INFO] Restaurando backup de certificados SSL (certs/acme.json)..."
    cp certs/acme.json /storage/traefik/data/acme.json
else
    # Se nao existe, cria vazio apenas se nao existir no destino
    if [ ! -f "/storage/traefik/data/acme.json" ]; then
        touch /storage/traefik/data/acme.json
    fi
fi

chmod 600 /storage/traefik/data/acme.json
# Remove stack existente
docker stack rm traefik 2>/dev/null; sleep 3
# Stack YAML
cat > /tmp/traefik.yaml << YAML
services:
  traefik:
    image: traefik:latest
    hostname: traefik.intranet.br
    command:
      - --global.checkNewVersion=false
      - --global.sendAnonymousUsage=false
      - --api.insecure=true
      - --log.level=INFO
      - --accesslog=true
      - --accesslog.filepath=/logs/access.log
      - --metrics.prometheus=true
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --entrypoints.web.http.redirections.entryPoint.permanent=true
      - --entrypoints.websecure.address=:443
      - --providers.swarm=true
      - --providers.swarm.endpoint=unix:///var/run/docker.sock
      - --providers.swarm.network=network_public
      - --providers.swarm.exposedbydefault=false
      - --certificatesresolvers.letsencrypt.acme.email=$EMAIL
      - --certificatesresolvers.letsencrypt.acme.storage=/data/acme.json
      - --certificatesresolvers.letsencrypt.acme.dnschallenge=true
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
      # Staging para evitar rate limit (comente para produção)
      # - --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
    ports:
      - 80:80
      - 443:443
      - 8080:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /storage/traefik/data:/data
      - /storage/traefik/logs:/logs
      - /storage/traefik/config:/config
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
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
networks:
  network_public:
    external: true
YAML
# Deploy
docker stack deploy -c /tmp/traefik.yaml traefik
echo
echo "[OK] Traefik deployed"
echo
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo
echo "Proximo: bash 03-portainer.sh"
echo