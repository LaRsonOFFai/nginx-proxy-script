#!/bin/bash

set -e

echo "=== Настройка nginx прокси для Remnawave (v4) ==="

# 🔒 Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запусти скрипт от root"
  exit 1
fi

# 📥 Ввод данных
read -p "Введите домен прокси (например cdn-static.online): " DOMAIN
read -p "Введите backend (например sub.cheapvpn.online): " BACKEND

# 🌐 Получаем IP сервера
SERVER_IP=$(curl -s ifconfig.me)

# 🌐 Проверка DNS
echo "Проверяем DNS..."
if ! command -v dig &> /dev/null; then
    echo "⚠ dig не установлен, устанавливаем dnsutils..."
    apt update
    apt install -y dnsutils
fi

DOMAIN_IP=$(dig +time=5 +short $DOMAIN | tail -n1)
if [ -z "$DOMAIN_IP" ]; then
  echo "⚠️ Домен не резолвится. Продолжим, проверка DNS пропущена."
else
  if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    echo "❌ Домен не указывает на этот сервер"
    echo "IP сервера: $SERVER_IP"
    echo "IP домена: $DOMAIN_IP"
    exit 1
  fi
  echo "✅ DNS ок"
fi

# 🔌 Проверка TCP доступности backend
echo "Проверяем backend TCP соединение..."
BACKEND_HOST=$(echo $BACKEND | cut -d'/' -f1)
if nc -z -w5 $BACKEND_HOST 443; then
    echo "✅ Backend доступен по TCP (порт 443)"
else
    echo "⚠️ Backend не доступен по TCP. Проверьте сервер."
fi

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
  apt install -y certbot
else
  echo "Certbot уже установлен"
fi

# 🔥 Удаление дефолтного конфига
rm -f /etc/nginx/sites-enabled/default

# ⚠️ Проверка существующего конфига
if [ -f /etc/nginx/sites-available/$DOMAIN ]; then
  echo "⚠️ Конфиг уже существует"
  read -p "Перезаписать? (y/n): " confirm
  [ "$confirm" != "y" ] && exit 1
fi

# ======================
# 1️⃣ Получаем SSL через standalone
# ======================
echo "Получаем SSL сертификат через certbot (standalone)..."
if ! certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN; then
  echo "❌ Не удалось получить сертификат. Проверьте порт 80 и DNS"
  exit 1
fi
echo "✅ SSL сертификат получен"

# ======================
# 2️⃣ Создаём nginx конфиг с HTTPS
# ======================
echo "Создаем nginx конфиг с HTTPS..."
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
        proxy_pass https://\$backend\$request_uri;

        proxy_http_version 1.1;
        proxy_set_header Host $BACKEND_HOST;
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
        proxy_ssl_name $BACKEND_HOST;
        client_max_body_size 50M;
    }
}
EOF

# 🔗 Активация и проверка nginx
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
echo "Проверяем nginx конфиг..."
nginx -t
systemctl reload nginx

echo "🎉 Готово! Прокси настроен: https://$DOMAIN"
