: "${STATIC_IP:?Missing STATIC_IP}"
: "${ROUTER_IP:?Missing ROUTER_IP}"
: "${DNS_IP:?Missing DNS_IP}"

# Get the active connection name for wlan0
CON_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep "^.*:wlan0$" | cut -d: -f1)

if [[ -z "$CON_NAME" ]]; then
    echo "❌ No active NetworkManager connection found for wlan0"
    exit 1
fi

echo "🔧 Configuring static IP for NetworkManager connection: $CON_NAME"

# Apply static IP settings
nmcli con mod "$CON_NAME" ipv4.addresses "$STATIC_IP/24"
nmcli con mod "$CON_NAME" ipv4.gateway "$ROUTER_IP"
nmcli con mod "$CON_NAME" ipv4.dns "$DNS_IP"
nmcli con mod "$CON_NAME" ipv4.method manual

# Bring the connection down and up to apply changes
nmcli con down "$CON_NAME" && nmcli con up "$CON_NAME"

echo "✅ Static IP configuration applied via NetworkManager"
