#!/bin/bash
set -e

echo "=== Remnawave nginx proxy setup (v13.6 — DNS pre-check) ==="
echo "🔧 Исправлено: NXDOMAIN (нет A-записи)"
echo "   + Автоматическая проверка DNS с помощью dig"
echo "   + dnsutils установлен автоматически"
echo "   + Чёткое сообщение + подтверждение перед SSL"
echo "   + Если DNS не настроен — скрипт остановится ДО попытки получения сертификата"

# 🔒 Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запусти скрипт от root (sudo bash $0)"
    exit 1
fi

# ======================
# Выбор режима установки
# ======================
read -p "Нужна ЧИСТАЯ установка? (y/n, по умолчанию n): " CLEAN
CLEAN=${CLEAN:-n}

# ======================
# Ввод данных
# ======================
read -p "Введите домен прокси (например example-proxy.site): " DOMAIN
read -p "Введите backend (например example-backend.site): " BACKEND
read -p "Введите email для SSL (например admin@example.com): " EMAIL

# ======================
# Очистка
# ======================
if [[ "$CLEAN" =~ ^[Yy]$ ]]; then
    echo "🧹 ЧИСТАЯ УСТАНОВКА: полная очистка..."
    systemctl stop nginx || true
    apt purge -y nginx nginx-common nginx-full nginx-light || true
    apt autoremove -y --purge || true
    rm -rf /etc/nginx \
           /var/log/nginx \
           /var/lib/nginx \
           /var/www/html \
           /root/.acme.sh \
           /etc/nginx/ssl
    echo "✅ Полная очистка завершена"
else
    echo "⚡ Обычный режим: очищаем только конфиги сайтов..."
    systemctl stop nginx || true
    rm -rf /etc/nginx/sites-available/* \
           /etc/nginx/sites-enabled/* \
           /etc/nginx/ssl
fi

# ======================
# Установка nginx + dnsutils (для проверки DNS)
# ======================
echo "📦 Устанавливаем nginx + dnsutils + зависимости..."
apt update
apt install -y nginx nginx-common curl socat idn dnsutils

# ======================
# Восстановление nginx.conf и mime.types
# ======================
echo "🔧 Восстанавливаем nginx.conf и mime.types..."
mkdir -p /etc/nginx/sites-available \
         /etc/nginx/sites-enabled \
         /etc/nginx/conf.d \
         /etc/nginx/modules-enabled \
         /var/log/nginx \
         /run/nginx \
         /var/www/html/.well-known/acme-challenge

if [ ! -f /etc/nginx/nginx.conf ]; then
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
fi

if [ ! -f /etc/nginx/mime.types ]; then
    cat > /etc/nginx/mime.types << 'EOT'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/atom+xml                  atom;
    application/rss+xml                   rss;
    text/plain                            txt;
    text/vnd.sun.j2me.app-descriptor      jad;
    text/vnd.wap.wml                      wml;
    text/x-component                      htc;
    image/png                             png;
    image/tiff                            tif tiff;
    image/vnd.wap.wbmp                    wbmp;
    image/x-icon                          ico;
    image/x-jng                           jng;
    image/x-ms-bmp                        bmp;
    image/svg+xml                         svg svgz;
    image/webp                            webp;
    application/java-archive              jar war ear;
    application/json                      json;
    application/mac-binhex40              hqx;
    application/msword                    doc;
    application/pdf                       pdf;
    application/postscript                ps eps ai;
    application/rtf                       rtf;
    application/vnd.apple.mpegurl         m3u8;
    application/vnd.google-earth.kml+xml  kml;
    application/vnd.google-earth.kmz      kmz;
    application/vnd.ms-excel              xls;
    application/vnd.ms-fontobject         eot;
    application/vnd.ms-powerpoint         ppt;
    application/vnd.oasis.opendocument.graphics     odg;
    application/vnd.oasis.opendocument.presentation  odp;
    application/vnd.oasis.opendocument.spreadsheet   ods;
    application/vnd.oasis.opendocument.text          odt;
    application/vnd.openxmlformats-officedocument.presentationml.presentation  pptx;
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet         xlsx;
    application/vnd.openxmlformats-officedocument.wordprocessingml.document   docx;
    application/vnd.wap.wmlc              wmlc;
    application/x-7z-compressed           7z;
    application/x-atom                    atom;
    application/x-bittorrent              torrent;
    application/x-bzip                    bz;
    application/x-bzip2                   bz2;
    application/x-chrome-extension        crx;
    application/x-cocoa                   cco;
    application/x-debian-package          deb;
    application/x-dvi                     dvi;
    application/x-font-truetype           ttf;
    application/x-font-woff               woff;
    application/x-httpd-cgi               cgi pl;
    application/x-java-archive-diff       jardiff;
    application/x-java-jnlp-file          jnlp;
    application/x-makeself                run;
    application/x-perl                    pl pm;
    application/x-pilot                   prc pdb;
    application/x-rar-compressed          rar;
    application/x-redhat-package-manager  rpm;
    application/x-sea                     sea;
    application/x-shockwave-flash         swf;
    application/x-stuffit                 sit;
    application/x-tcl                     tcl;
    application/x-x509-ca-cert            der pem crt;
    application/x-xpinstall               xpi;
    application/xhtml+xml                 xhtml;
    application/xspf+xml                  xspf;
    application/zip                       zip;
    application/octet-stream              bin exe dll;
    audio/midi                            mid midi kar;
    audio/mpeg                            mp3;
    audio/ogg                             ogg;
    audio/x-m4a                           m4a;
    audio/x-realaudio                     ra;
    video/3gpp                            3gpp 3gp;
    video/mp2t                            ts;
    video/mp4                             mp4;
    video/mpeg                            mpeg mpg;
    video/ogg                             ogv;
    video/quicktime                       mov;
    video/webm                            webm;
    video/x-flv                           flv;
    video/x-m4v                           m4v;
    video/x-mng                           mng;
    video/x-ms-asf                        asx asf;
    video/x-ms-wmv                        wmv;
    video/x-msvideo                       avi;
}
EOT
fi

# ======================
# Установка acme.sh
# ======================
if ! command -v acme.sh &>/dev/null; then
    echo "📦 Устанавливаем acme.sh..."
    curl -s https://get.acme.sh | sh
    export PATH="$HOME/.acme.sh:$PATH"
fi

# ======================
# Директории
# ======================
echo "🔥 Создаём директории..."
mkdir -p "/etc/nginx/ssl/$DOMAIN"
mkdir -p /var/www/html/.well-known/acme-challenge

# ======================
# Временный HTTP-конфиг
# ======================
echo "🔥 Создаём временный HTTP-конфиг..."
cat > /etc/nginx/sites-available/"$DOMAIN" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;

    location /.well-known/acme-challenge/ {
        allow all;
    }

    location / {
        return 301 http://\$host\$request_uri;
    }
}
EOF

ln -sf /etc/nginx/sites-available/"$DOMAIN" /etc/nginx/sites-enabled/

nginx -t && echo "✅ Временный nginx-конфиг OK"
systemctl enable nginx --now

# ======================
# Автоматическое открытие портов
# ======================
echo "🔓 Открываем порты 80 и 443..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp comment 'ACME HTTP Challenge'
    ufw allow 443/tcp comment 'HTTPS'
    ufw reload || true
    echo "✅ ufw: порты открыты"
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --reload || true
    echo "✅ firewalld: порты открыты"
fi

iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
ip6tables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
ip6tables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true

# ======================
# Публичный IP + ПРОВЕРКА DNS (главное исправление)
# ======================
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || echo "не удалось определить")
echo "🌍 Ваш публичный IP: $PUBLIC_IP"

echo "🔍 Проверяем DNS-запись для $DOMAIN..."
RESOLVED_IP=$(dig +short A "$DOMAIN" | head -n1 || echo "")

if [ -z "$RESOLVED_IP" ]; then
    echo "❌ DNS ОШИБКА: NXDOMAIN"
    echo "   Домен $DOMAIN вообще не резолвится!"
    echo "   Нужно создать A-запись:"
    echo "   $DOMAIN  →  $PUBLIC_IP"
else
    if [ "$RESOLVED_IP" = "$PUBLIC_IP" ]; then
        echo "✅ DNS OK: $DOMAIN → $PUBLIC_IP"
    else
        echo "⚠️  DNS НЕ СОВПАДАЕТ: резолвится на $RESOLVED_IP (а должен на $PUBLIC_IP)"
    fi
fi

echo ""
echo "⏳ Если вы только что добавили A-запись в панели хостинга — подождите 30–120 секунд (пропагация DNS)"
read -p "DNS настроен и готов к получению SSL? (y/n): " DNS_READY
if [[ ! "$DNS_READY" =~ ^[Yy]$ ]]; then
    echo "Сначала настройте A-запись $DOMAIN → $PUBLIC_IP и запустите скрипт заново."
    exit 1
fi

# ======================
# Получение SSL
# ======================
SSL_DIR="/etc/nginx/ssl/$DOMAIN"

echo "🔑 Получаем SSL-сертификат от Let's Encrypt..."
"$HOME/.acme.sh"/acme.sh --register-account -m "$EMAIL" || true

"$HOME/.acme.sh"/acme.sh --issue \
    -d "$DOMAIN" \
    --server letsencrypt \
    --webroot /var/www/html \
    --key-file "$SSL_DIR/privkey.key" \
    --fullchain-file "$SSL_DIR/fullchain.pem" \
    --reloadcmd "systemctl reload nginx"

# ======================
# Проверка сертификата
# ======================
if [ ! -f "$SSL_DIR/fullchain.pem" ] || [ ! -f "$SSL_DIR/privkey.key" ]; then
    echo "❌ SSL НЕ ПОЛУЧЕН"
    echo "   Самая частая причина — DNS ещё не обновился."
    echo "   Подождите 2–5 минут и запустите скрипт заново."
    exit 1
fi

echo "✅ SSL-сертификат успешно получен!"

# ======================
# Финальный конфиг
# ======================
echo "⚡ Настраиваем финальный HTTPS + proxy..."
cat > /etc/nginx/sites-available/"$DOMAIN" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.key;

    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    location / {
        set \$backend "$BACKEND";
        proxy_pass https://\$backend\$request_uri;

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

ln -sf /etc/nginx/sites-available/"$DOMAIN" /etc/nginx/sites-enabled/
nginx -t && echo "✅ Финальный nginx-конфиг OK"
systemctl restart nginx

echo "🎉 ГОТОВО!"
echo "Прокси работает:"
echo "   https://$DOMAIN  →  проксирует $BACKEND"
echo "   http://$DOMAIN   →  редирект на HTTPS"
echo "SSL от Let's Encrypt установлен автоматически."
