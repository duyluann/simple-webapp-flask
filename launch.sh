#!/usr/bin/env bash
set -euo pipefail

# Check Docker
if ! command -v docker &>/dev/null; then
  echo "Error: Docker not installed. Install from https://docs.docker.com/get-docker/"
  exit 1
fi

# Check port 80
if nc -zw2 127.0.0.1 80 2>/dev/null; then
  echo "Warning: something already listening on port 80 -- Let's Encrypt HTTP-01 may fail"
else
  echo "Note: port 80 must be open on your firewall for Let's Encrypt to issue certificates"
fi

# Detect public IP (IPv4 only — sslip.io requires IPv4)
PUBLIC_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s api.ipify.org 2>/dev/null || echo "")
if [ -z "$PUBLIC_IP" ]; then
  echo "Error: could not detect public IPv4 address"
  exit 1
fi
DOMAIN="simple-webapp-flask.${PUBLIC_IP}.sslip.io"
echo "Domain: $DOMAIN"

# Detect project structure and launch
if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
  echo "Detected existing docker-compose — adding Traefik overlay"
  APP_SERVICE=$(docker compose config --services 2>/dev/null | grep -v '^traefik$' | head -1 || echo "")
  if [ -z "$APP_SERVICE" ]; then
    echo "Error: could not detect app service name from docker-compose"
    exit 1
  fi
  docker network create traefik-net 2>/dev/null || true
  touch acme.json && chmod 600 acme.json
  cat > docker-compose.override.yml << OVERRIDE_EOF
services:
  traefik:
    image: traefik:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=luanlee1997@gmail.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
    restart: unless-stopped
    networks:
      - traefik-net
  ${APP_SERVICE}:
    expose:
      - "8080"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${APP_SERVICE}.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.${APP_SERVICE}.entrypoints=websecure"
      - "traefik.http.routers.${APP_SERVICE}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${APP_SERVICE}.loadbalancer.server.port=8080"
    restart: unless-stopped
    networks:
      - traefik-net
networks:
  traefik-net:
    external: true
OVERRIDE_EOF
  docker compose up -d --build
elif [ -f Dockerfile ]; then
  echo "Detected Dockerfile — generating docker-compose.yml"
  cat > docker-compose.yml << 'COMPOSE_EOF'
services:
  traefik:
    image: traefik:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=luanlee1997@gmail.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
    restart: unless-stopped
  simple-webapp-flask:
    build:
      context: .
    expose:
      - "8080"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.simple-webapp-flask.rule=Host(`__DOMAIN__`)"
      - "traefik.http.routers.simple-webapp-flask.entrypoints=websecure"
      - "traefik.http.routers.simple-webapp-flask.tls.certresolver=letsencrypt"
      - "traefik.http.services.simple-webapp-flask.loadbalancer.server.port=8080"
    restart: unless-stopped
COMPOSE_EOF
  sed -i'' "s|__DOMAIN__|$DOMAIN|g" docker-compose.yml
  touch acme.json && chmod 600 acme.json
  docker compose up -d --build
else
  echo "Error: no Dockerfile or docker-compose.yml found in current directory"
  exit 1
fi

echo ""
echo "Your app is live at: https://simple-webapp-flask.${PUBLIC_IP}.sslip.io"
echo "Note: SSL certificate issuance takes ~30 seconds after startup"
