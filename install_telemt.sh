#!/bin/sh

set -e

echo "=== Telemt installer for Entware ==="

# --- Detect public IP from ISP interface ---
echo "Detecting public IP from interface ISP..."
AUTO_IP=$(ndmc -c 'show interface ISP' | grep "address:" | awk '{print $2}' | head -n 1)

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

echo ""
echo "Installing Telemt..."
opkg update
opkg install https://test.entware.net/mipssf-k3.4/4test/aa/telemt_3.4.5-1_aarch64-3.10.ipk
opkg install openssl-util
opkg install jq

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

echo "Restarting Telemt using built-in init script..."
/opt/etc/init.d/S99telemt restart

# --- Generate Telegram link ---

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
