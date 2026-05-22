#!/bin/bash
cat << 'EOF' | sudo tee /etc/nginx/sites-available/panelhide.su > /dev/null
server {
    listen 80;
    listen [::]:80;

    server_name panelhide.su www.panelhide.su;

    location /logo/ {
        alias /var/www/html/;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF
sudo systemctl reload nginx
