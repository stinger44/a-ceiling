#!/bin/bash
# Migration script from Nginx to Caddy

# 1. Run backup
bash ./_backup_nginx_before_caddy.sh

# 2. Stop Nginx and Certbot timer
echo "Stopping Nginx..."
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo systemctl stop certbot.timer
sudo systemctl disable certbot.timer

# 3. Install Caddy (Ubuntu/Debian)
echo "Installing Caddy..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# 4. Apply Caddyfile
echo "Applying Caddyfile..."
sudo cp ./Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy

echo "Migration complete. Check status with: systemctl status caddy"
