#!/bin/bash

set -e

echo "=== Настройка nginx прокси ==="

# 🔒 Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запусти скрипт от root"
  exit 1
fi

# 📥 Ввод данных
read -p "Введите домен (например proxy-example.site): " DOMAIN
read -p "Введите backend (например backend-example.site): " BACKEND

# 🌐 Получаем IP сервера
SERVER_IP=$(curl -s ifconfig.me)

# 🌐 Проверка DNS
echo "Проверяем DNS..."
DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

if [ -z "$DOMAIN_IP" ]; then
  echo "❌ Домен не резолвится"
  exit 1
fi

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
  echo "❌ Домен не указывает на этот сервер"
  echo "IP сервера: $SERVER_IP"
  echo "IP домена: $DOMAIN_IP"
  exit 1
fi

echo "✅ DNS ок"

# 🔌 Проверка backend
echo "Проверяем backend..."
if ! curl -Is https://$BACKEND | head -n 1 | grep -E "200|301|302" > /dev/null; then
  echo "❌ Backend недоступен или не отвечает корректно"
  exit 1
fi

echo "✅ Backend доступен"

# 📦 Установка nginx
if ! command -v nginx &> /dev/null; then
  echo "Устанавливаем nginx..."
  apt update
  apt install -y nginx
else
  echo "Nginx уже установлен"
fi

# 📦 Установка certbot
if ! command -v certbot &> /dev/null; then
  echo "Устанавливаем certbot..."
  apt install -y certbot python3-certbot-nginx
else
  echo "Certbot уже установлен"
fi

# 🔥 Удаление дефолта
rm -f /etc/nginx/sites-enabled/default

# ⚠️ Проверка существующего конфига
if [ -f /etc/nginx/sites-available/$DOMAIN ]; then
  echo "⚠️ Конфиг уже существует"
  read -p "Перезаписать? (y/n): " confirm
  [ "$confirm" != "y" ] && exit 1
fi

# 📝 Создание конфига
echo "Создаем nginx конфиг..."

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

# 🔗 Активация
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# 🔍 Проверка nginx
echo "Проверяем nginx конфиг..."
if ! nginx -t; then
  echo "❌ Ошибка в конфиге nginx"
  exit 1
fi

systemctl reload nginx

# 🔐 Проверка порта 80
if ss -tulpn | grep :80 > /dev/null; then
  echo "⚠️ Порт 80 занят (это нормально если nginx)"
fi

# 🔐 Получение SSL
echo "Получаем SSL..."
if ! certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN; then
  echo "❌ Ошибка при получении SSL"
  echo "👉 Проверь порт 80 и DNS"
  exit 1
fi

echo "🎉 Готово! Прокси настроен: https://$DOMAIN"
