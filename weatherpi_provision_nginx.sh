#!/bin/bash
set -euo pipefail

log() { echo "[+] $1"; }

## Usage:
# scp -i /mnt/c/Users/sqlpa/.ssh/raspi_key /mnt/c/Users/sqlpa/weatherpi/weatherpi_provision_nginx.sh raspi@192.168.9.107:/home/raspi/
# chmod +x weatherpi_provision_nginx.sh
# Provision: sudo ./weatherpi_provision_nginx.sh
# Reset:     sudo ./weatherpi_provision_nginx.sh --reset

HOSTNAME="weatherpi02.local"
WEBROOT="/var/www/weatherpi02"
NGCONF="/etc/nginx/sites-available/default"
BACKUP="/etc/nginx/sites-available/default.bak"
CERTDIR="/etc/ssl/weatherpi02"

# ── Reset Mode ────────────────────────────────────────────────
if [[ "${1:-}" == "--reset" ]]; then
    echo "[!] Reset mode activated. Removing Nginx, certs, and configs..."

    sudo systemctl stop nginx || true
    sudo systemctl disable nginx || true

    echo "[+] Removing Nginx and related packages..."
    sudo apt purge -y nginx nginx-common nginx-core || true
    sudo apt autoremove -y

    echo "[+] Removing UFW rules..."
    sudo ufw delete allow 'Nginx Full' || true

    echo "[+] Removing web root..."
    sudo rm -rf /var/www/weatherpi02

    echo "[+] Removing self-signed certs..."
    sudo rm -rf /etc/ssl/weatherpi02

    echo "[+] Restoring original Nginx config if backup exists..."
    if [ -f /etc/nginx/sites-available/default.bak ]; then
        sudo mv /etc/nginx/sites-available/default.bak /etc/nginx/sites-available/default
    fi

    echo "[+] Reset complete. System cleaned."
    exit 0
fi

# ── Install Nginx and UFW ─────────────────────────────────────
log "Updating packages..."
sudo apt update -y

for pkg in nginx ufw openssl; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        log "Installing $pkg..."
        sudo apt install -y "$pkg"
    else
        log "$pkg already installed."
    fi
done

# ── Configure UFW ─────────────────────────────────────────────
if ! sudo ufw status | grep -q "Nginx Full"; then
    log "Allowing HTTPS through firewall..."
    sudo ufw allow 'Nginx Full'
fi

if ! sudo ufw status | grep -q "Status: active"; then
    log "Enabling UFW..."
    sudo ufw --force enable
else
    log "UFW already active."
fi

# ── Create Web Root ───────────────────────────────────────────
if [ ! -d "$WEBROOT" ]; then
    log "Creating web root at $WEBROOT..."
    sudo mkdir -p "$WEBROOT"
    sudo chown www-data:www-data "$WEBROOT"
    sudo chmod 750 "$WEBROOT"
else
    log "Web root already exists."
fi

# ── Create Default Page ───────────────────────────────────────
INDEX="$WEBROOT/index.html"
if [ ! -f "$INDEX" ]; then
    log "Creating default index page..."
    cat <<EOF | sudo tee "$INDEX" > /dev/null
<!DOCTYPE html>
<html><head><title>WeatherPi02</title></head>
<body><h1>Secure WeatherPi02 is online (local)</h1></body></html>
EOF
else
    log "Index page already exists."
fi

# ── Generate Self-Signed Certificate ──────────────────────────
if [ ! -f "$CERTDIR/weatherpi02.crt" ]; then
    log "Generating self-signed certificate..."
    sudo mkdir -p "$CERTDIR"
    sudo openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$CERTDIR/weatherpi02.key" \
        -out "$CERTDIR/weatherpi02.crt" \
        -subj "/CN=$HOSTNAME"
else
    log "Self-signed certificate already exists."
fi

# ── Backup and Harden Nginx Config ────────────────────────────
if [ ! -f "$BACKUP" ]; then
    log "Backing up default Nginx config..."
    sudo cp "$NGCONF" "$BACKUP"
fi

if ! grep -q "server_name $HOSTNAME;" "$NGCONF"; then
    log "Writing HTTPS-only Nginx config..."
    cat <<EOF | sudo tee "$NGCONF" > /dev/null
server {
    listen 443 ssl;
    server_name $HOSTNAME;

    root $WEBROOT;
    index index.html;

    ssl_certificate $CERTDIR/weatherpi02.crt;
    ssl_certificate_key $CERTDIR/weatherpi02.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\. {
        deny all;
    }

    client_max_body_size 1M;
}
EOF
else
    log "Nginx config already includes HTTPS."
fi

# ── Validate and Restart ──────────────────────────────────────
log "Testing Nginx config..."
sudo nginx -t

log "Restarting Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

log "Setup complete. Visit https://$HOSTNAME (you may need to accept the self-signed cert)."