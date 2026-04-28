#!/bin/sh

set -e

PANEL_CONFIG="/opt/etc/telemt-panel/config.toml"
TELEMT_CONFIG="/opt/etc/telemt/config.toml"
# Определяем архитектуру
ARCH=$(uname -m)

case "$ARCH" in
    aarch64)
        IPK_URL="https://test.entware.net/mipssf-k3.4/4test/aa/telemt-panel_0.5.2-2_aarch64-3.10.ipk"
        ;;
    mips|mipsel)
        IPK_URL="https://test.entware.net/mipssf-k3.4/4test/le/telemt-panel_0.5.2-2_mipsel-3.4.ipk"
        ;;
    *)
        echo "Неизвестная архитектура: $ARCH"
        echo "Укажи URL пакета вручную, отредактировав скрипт."
        exit 1
        ;;
esac

echo "Определена архитектура: $ARCH"
echo "Будет установлен пакет: $IPK_URL"
echo ""

if [ -x /opt/etc/init.d/S99telemt-panel ]; then
    /opt/etc/init.d/S99telemt-panel stop >/dev/null 2>&1 || true
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
opkg --nodeps --force-depends install "$IPK_URL" 

echo "[3] Введите пароль который будет использоваться для входа в панель управления:"
read PASS
PASSWORD_HASH=$(echo "$PASS" | telemt-panel hash-password)
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
echo "пользователь admin"
