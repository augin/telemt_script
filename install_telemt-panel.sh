#!/bin/sh

set -e

IPK_URL="https://test.entware.net/mipssf-k3.4/4test/aa/telemt-panel_0.5.2-2_aarch64-3.10.ipk"
PANEL_CONFIG="/opt/etc/telemt-panel/config.toml"
TELEMT_CONFIG="/opt/etc/telemt/config.toml"

if [ -x /opt/etc/init.d/S99telemt-panel ]; then
    /opt/etc/init.d/S99telemt-panel stop
fi


DEFAULT_PORT=8080

echo "[1] Проверка занятости порта $DEFAULT_PORT"

check_port() {
    PORT=$1
    if netstat -tuln | grep -q ":$PORT "; then
        echo "⚠️  Порт $PORT уже занят!"
        echo "Процесс:"
        netstat -tulnp | grep ":$PORT " || true
        return 1
    fi
    return 0
}

if ! check_port "$DEFAULT_PORT"; then
    echo ""
    echo "Введите новый порт для telemt-panel:"
    read -r NEW_PORT

    while ! check_port "$NEW_PORT"; do
        echo "Порт $NEW_PORT тоже занят. Введите другой:"
        read -r NEW_PORT
    done

    LISTEN_PORT="$NEW_PORT"
else
    LISTEN_PORT="$DEFAULT_PORT"
fi

echo "Используем порт: $LISTEN_PORT"
echo ""

echo "[2] Установка telemt-panel"
opkg install "$IPK_URL"

echo "[3] Введите пароль который будет использоваться для входа в панель управления"
PASSWORD_HASH=$(telemt-panel hash-password 2>/dev/null | grep '^\$2')
echo "password_hash = $PASSWORD_HASH"

echo "[4] Генерация jwt_secret"
JWT_SECRET=$(openssl rand -hex 32)
echo "jwt_secret = $JWT_SECRET"

echo "[5] Чтение auth_header из $TELEMT_CONFIG"
AUTH_HEADER=$(grep -E '^auth_header' "$TELEMT_CONFIG" | sed 's/.*= "\(.*\)"/\1/')
echo "auth_header = $AUTH_HEADER"

echo "[6] Создание нового конфига telemt-panel"

cat > "$PANEL_CONFIG" <<EOF
listen = "0.0.0.0:$LISTEN_PORT"

[telemt]
url = "http://127.0.0.1:9091"
auth_header = "$AUTH_HEADER"

[panel]

[tls]

[geoip]

[auth]
username = "admin"
password_hash = "$PASSWORD_HASH"
jwt_secret = "$JWT_SECRET"
session_ttl = "24h"

[users]
EOF

echo "[7] Перезапуск telemt-panel"
/opt/etc/init.d/S99telemt-panel restart

echo "[8] Готово. Конфиг записан в $PANEL_CONFIG"
echo "telemt-panel запущен и слушает порт: $LISTEN_PORT"
