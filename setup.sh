#!/bin/bash

read -p "Введите домен (например proxy-example.site): " DOMAIN
read -p "Введите backend (например backend-example.site): " BACKEND

echo "Проверяем зависимости..."

if ! command -v nginx &> /dev/null
then
    echo "Nginx не найден, устанавливаем..."
    apt update
    apt install -y nginx
else
    echo "Nginx уже установлен"
fi

if ! command -v certbot &> /dev/null
then
    echo "Certbot не найден, устанавливаем..."
    apt update
    apt install -y certbot python3-certbot-nginx
else
    echo "Certbot уже установлен"
fi

echo "Удаляем дефолтный конфиг (если есть)..."
rm -f /etc/nginx/sites-enabled/default

echo "Создаем конфиг nginx..."

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    location / {
        set \$backend "$BACKEND";
        proxy_pass https://\$backend;

        proxy_http_version 1.1;

        proxy_set_header Host $BACKEND;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Connection "";

        proxy_buffering off;
        proxy_cache off;

        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;

        proxy_buffers 8 32k;
        proxy_buffer_size 64k;

        proxy_ssl_server_name on;
        proxy_ssl_name $BACKEND;

        client_max_body_size 50M;
    }
}
EOF

echo "Активируем сайт..."
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

echo "Проверяем конфиг nginx..."
nginx -t || { echo "Ошибка в конфиге!"; exit 1; }

systemctl reload nginx

echo "Получаем SSL сертификат..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

echo "Готово!"
