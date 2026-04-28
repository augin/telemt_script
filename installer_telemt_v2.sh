#!/bin/sh

set -e

echo "=== Telemt installer for Entware ==="
echo "Установка зависимостей"
opkg update
opkg install openssl-util
opkg install jq

# останавливаем telemt если уже стоит и запущен
if [ -x /opt/etc/init.d/S99telemt ]; then
    /opt/etc/init.d/S99telemt stop >/dev/null 2>&1 || true
fi


# --- Detect public IP via default route ---
echo "Detecting public IP via default route..."

DEF_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)

if [ -z "$DEF_IFACE" ]; then
    echo "ERROR: Cannot detect default route interface!"
    exit 1
fi

echo "Default route interface: $DEF_IFACE"

AUTO_IP=$(ip -4 addr show "$DEF_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)

if [ -z "$AUTO_IP" ]; then
    echo "ERROR: Cannot detect IP address on interface $DEF_IFACE!"
    exit 1
fi

echo "Detected public IP: $AUTO_IP"


# --- Detect TLS domain ending with netcraze.io ---
echo "Detecting TLS domain (ending with netcraze.io)..."
AUTO_DOMAIN=$(ndmc -c 'ip http ssl acme list' | grep "domain:" | awk '{print $2}' | grep "netcraze.io" | head -n 1)


# --- Ask parameters ---
printf "Enter port (default 1443): "
read PORT
PORT=${PORT:-1443}

printf "Enter public IP (default $AUTO_IP): "
read PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}

printf "Enter TLS domain (default $AUTO_DOMAIN): "
read TLS_DOMAIN
TLS_DOMAIN=${TLS_DOMAIN:-$AUTO_DOMAIN}

printf "Enter username (default user1): "
read USERNAME
USERNAME=${USERNAME:-user1}


# --- Auto-generate secret ---
echo "Generating HEX16 secret..."
USER_SECRET=$(openssl rand -hex 16)
echo "Generated secret: $USER_SECRET"

# --- Auto-generate auth_header ---
echo "Generating API auth_header..."
AUTH_HEADER=$(openssl rand -hex 32)
echo "Generated auth_header: $AUTH_HEADER"


# --- Select upstream interface from ip a ---
echo "Выберете интерфейс через который прокси будет выходить в мир"

IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -v '^sit' | grep -v '^ip6tnl')

echo "Доступные интерфейсы:"
i=1
for iface in $IFACES; do
    echo "  $i) $iface"
    eval "iface_$i=$iface"
    i=$((i+1))
done

printf "Select upstream interface number (default 1): "
read IFNUM
IFNUM=${IFNUM:-1}

UP_IFACE=$(eval echo "\$iface_$IFNUM")
echo "Selected interface: $UP_IFACE"


# --- Check if port is free ---
while true; do
    echo "Checking if port $PORT is free..."
    if netstat -tuln | grep ":$PORT " >/dev/null 2>&1; then
        echo "Port $PORT is already in use!"
        printf "Enter another port: "
        read PORT
    else
        echo "Port OK."
        break
    fi
done


# --- Validate domain ---
echo "Checking domain resolution..."
if ! nslookup "$TLS_DOMAIN" >/dev/null 2>&1 && ! ping -c1 "$TLS_DOMAIN" >/dev/null 2>&1; then
    echo "WARNING: Domain $TLS_DOMAIN does not resolve!"
    echo "Press Enter to continue anyway or Ctrl+C to abort."
    read _
else
    echo "Domain OK."
fi


echo ""
echo "Installing dependencies..."

opkg install wget-ssl || opkg install wget


# --- Download latest Telemt release (aarch64 + mipsel) ---
echo "=== Installing Telemt (latest release) ==="

TMPDIR="/opt/tmp/telemt_dl"
mkdir -p "$TMPDIR"

ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

case "$ARCH" in
    aarch64)
        TELEMT_FILE="telemt-aarch64-linux-musl.tar.gz"
        ;;
    mips|mipsel|mips32|mips32r2)
        TELEMT_FILE="telemt-mipsel-linux-musl.tar.gz"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "Supported: aarch64, mipsel"
        exit 1
        ;;
esac

echo "Detecting latest Telemt version from GitHub..."
LATEST_VER=$(wget -qO- https://api.github.com/repos/telemt/telemt/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)

if [ -z "$LATEST_VER" ]; then
    echo "ERROR: Cannot detect latest version from GitHub!"
    exit 1
fi

echo "Latest version: $LATEST_VER"

TARBALL_URL="https://github.com/telemt/telemt/releases/download/${LATEST_VER}/${TELEMT_FILE}"
TARBALL_PATH="$TMPDIR/telemt.tar.gz"

echo "Downloading Telemt from:"
echo "  $TARBALL_URL"

wget -O "$TARBALL_PATH" "$TARBALL_URL"

echo "Extracting Telemt..."
tar -xzf "$TARBALL_PATH" -C "$TMPDIR"

if [ ! -f "$TMPDIR/telemt" ]; then
    echo "ERROR: telemt binary not found in archive!"
    exit 1
fi

echo "Installing Telemt binary to /opt/usr/bin..."
mkdir -p /opt/usr/bin
cp "$TMPDIR/telemt" /opt/usr/bin/telemt
chmod +x /opt/usr/bin/telemt

echo "Telemt binary installed for architecture: $ARCH"


# --- Install init script ---
echo "Installing init script..."

mkdir -p /opt/etc/init.d

cat > /opt/etc/init.d/S99telemt <<'EOF'
#!/bin/sh

ENABLED=yes
PROCS=telemt
ARGS="-d /opt/etc/$PROCS/config.toml"
PREARGS=""
DESC="Telemt MTProxy"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF

chmod +x /opt/etc/init.d/S99telemt

echo "Init script installed."


# --- Prepare config directory ---
mkdir -p /opt/etc/telemt
cd /opt/etc/telemt

# --- Create tlsfront directory ---
echo "Creating tlsfront directory..."
mkdir -p tlsfront

# --- WAN interface is fixed: ISP ---
WAN_IF="ISP"
echo "WAN interface set to: $WAN_IF"
echo "No firewall/NAT rules required on Keenetic for local services."

echo "Writing config.toml..."

cat > config.toml <<EOF
[general]
use_middle_proxy = true
log_level = "silent"
upstream_connect_failfast_hard_errors = true

[server]
port = $PORT

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = [ "127.0.0.1/32", "::1/128" ]
minimal_runtime_enabled = true
minimal_runtime_cache_ttl_ms = 1000
read_only = true
auth_header = "$AUTH_HEADER"

[[server.listeners]]
ip = "$PUBLIC_IP"

[censorship]
tls_domain = "$TLS_DOMAIN"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"
mask_host = "$TLS_DOMAIN"
mask_shape_hardening_aggressive_mode = true

[access.users]
$USERNAME = "$USER_SECRET"

[[upstreams]]
type = "direct"
interface = "$UP_IFACE"
EOF

echo "Restarting Telemt..."
/opt/etc/init.d/S99telemt restart

echo ""
echo "=== Telemt installed and running ==="
echo "Port: $PORT"
echo "IP: $PUBLIC_IP"
echo "TLS domain: $TLS_DOMAIN"
echo "User: $USERNAME"
echo "Secret: $USER_SECRET"
echo "Upstream interface: $UP_IFACE"
echo "WAN interface: $WAN_IF"
echo "tlsfront directory: /opt/etc/telemt/tlsfront"
echo ""
curl -H "Authorization: $AUTH_HEADER" -s http://127.0.0.1:9091/v1/users | jq -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""'
echo ""
echo "⚠️ Не забудьте открыть порт $PORT в межсетевом экране!!!"
echo "Межсетевой экран -> Добавить правило -> Порт назначения равен $PORT. ✅ Включить правило. -> Сохранить"
