#!/bin/bash
# Rollback script from Caddy to Nginx

echo "Stopping Caddy..."
sudo systemctl stop caddy
sudo systemctl disable caddy

echo "Starting Nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

echo "Rollback complete. Nginx should be back online."
