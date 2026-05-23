# Check Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker not installed. Install from https://docs.docker.com/get-docker/"
    exit 1
}

# Check port 80
$portTest = Test-NetConnection -ComputerName localhost -Port 80 -WarningAction SilentlyContinue
if ($portTest.TcpTestSucceeded) {
    Write-Warning "Something already listening on port 80 -- Let's Encrypt HTTP-01 may fail"
} else {
    Write-Host "Note: port 80 must be open on your firewall for Let's Encrypt to issue certificates"
}

# Detect public IP (IPv4 only — sslip.io requires IPv4)
try {
    $PublicIP = (Invoke-WebRequest -Uri 'https://api4.ipify.org' -UseBasicParsing).Content.Trim()
} catch {
    try {
        $PublicIP = (Invoke-WebRequest -Uri 'https://ipv4.icanhazip.com' -UseBasicParsing).Content.Trim()
    } catch {
        Write-Error "Error: could not detect public IPv4 address"; exit 1
    }
}
$Domain = "simple-webapp-flask.$PublicIP.sslip.io"
Write-Host "Domain: $Domain"

# Write docker-compose.yml
@"
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

"@ -replace '__DOMAIN__', $Domain | Set-Content docker-compose.yml

# Create acme.json (required by Traefik)
New-Item -ItemType File -Force acme.json | Out-Null

# Launch
docker compose up -d

Write-Host ""
Write-Host "Your app is live at: https://simple-webapp-flask.$PublicIP.sslip.io"
Write-Host "Note: SSL certificate issuance takes ~30 seconds after startup"
