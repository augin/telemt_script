#!/bin/sh

set -e

echo "=== Telemt installer for Entware (universal arch) ==="

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
echo "Detecting available upstream interfaces from 'ip a'..."

IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -v '^sit' | grep -v '^ip6tnl')

echo "Available interfaces:"
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

# --- Check if port is free (loop until free) ---
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

# --- Detect architecture ---
echo "Detecting CPU architecture..."
ARCH=$(uname -m)

case "$ARCH" in
    aarch64)
        TELEMT_URL="https://test.entware.net/mipssf-k3.4/4test/aa/telemt_3.4.5-1_aarch64-3.10.ipk"
        ;;
    mips)
        TELEMT_URL="https://test.entware.net/mipssf-k3.4/4test/be/telemt_3.4.8-1_mips-3.4.ipk"
        ;;
    mipsel)
        TELEMT_URL="https://test.entware.net/mipssf-k3.4/4test/le/telemt_3.4.8-1_mipsel-3.4.ipk"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH"
echo "Using Telemt package:"
echo "  $TELEMT_URL"

echo "Installing Telemt..."
opkg update
opkg install "$TELEMT_URL"
opkg install openssl-util
opkg install jq

mkdir -p /opt/etc/telemt
cd /opt/etc/telemt

# --- Create tlsfront directory ---
echo "Creating tlsfront directory..."
mkdir -p tlsfront

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

echo "Restarting Telemt using built-in init script..."
/opt/etc/init.d/S99telemt restart

echo ""
echo "=== Telemt installed and running ==="
echo "Port: $PORT"
echo "IP: $PUBLIC_IP"
echo "TLS domain: $TLS_DOMAIN"
echo "User: $USERNAME"
echo "Secret: $USER_SECRET"
echo "Upstream interface: $UP_IFACE"
echo "tlsfront directory: /opt/etc/telemt/tlsfront"
echo ""

curl -H "Authorization: $AUTH_HEADER" -s http://127.0.0.1:9091/v1/users | jq -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""'

