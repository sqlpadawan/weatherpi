#!/bin/bash
set -e

## Usage:
## chmod +x weatherpi_provision.sh
## sudo ./weatherpi_provision.sh \
##   weatherpi \
##   192.168.9.105 \
##   192.168.9.1 \
##   192.168.9.1 \
##   raspi

### 🧠 Parse arguments
NEW_HOSTNAME="$1"
STATIC_IP="$2"
ROUTER_IP="$3"
DNS_IP="$4"
USERNAME="$5"

if [[ -z "$NEW_HOSTNAME" || -z "$STATIC_IP" || -z "$ROUTER_IP" || -z "$DNS_IP" || -z "$USERNAME" ]]; then
  echo "❌ Usage: $0 <hostname> <static_ip> <router_ip> <dns_ip> <username>"
  exit 1
fi

echo "🔧 Starting Raspberry Pi provisioning for $NEW_HOSTNAME with user $USERNAME..."

USE_DHCPCD=false
if systemctl is-active --quiet dhcpcd; then
  USE_DHCPCD=true
fi

### 1. Update system
echo "📦 Upgrading packages non-interactively..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get -y -o Dpkg::Options::="--force-confold" upgrade | tee /var/log/pi_upgrade.log

### 2. Enable I2C
echo "🔌 Enabling I2C..."
sudo raspi-config nonint do_i2c 0

### 3. Conditionally set hostname
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" != "$NEW_HOSTNAME" ]]; then
  echo "🖥️ Updating hostname from $CURRENT_HOSTNAME to $NEW_HOSTNAME..."
  echo "$NEW_HOSTNAME" | sudo tee /etc/hostname
  sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
  sudo hostnamectl set-hostname "$NEW_HOSTNAME"
else
  echo "✅ Hostname already set to $NEW_HOSTNAME. Skipping."
fi

### 4. Conditionally set static IP on wlan0
echo "🌐 Checking static IP configuration for wlan0..."

if $USE_DHCPCD; then
  echo "📄 Using dhcpcd for static IP configuration..."
  DHCPCD_FILE="/etc/dhcpcd.conf"
  DESIRED_BLOCK=$(cat <<EOF
interface wlan0
static ip_address=${STATIC_IP}/24
static routers=${ROUTER_IP}
static domain_name_servers=${DNS_IP}
EOF
  )
  CURRENT_BLOCK=$(awk '/^interface wlan0$/,/^$/' "$DHCPCD_FILE" 2>/dev/null || echo "")
  if [[ "$CURRENT_BLOCK" != "$DESIRED_BLOCK" ]]; then
    echo "🔧 Updating static IP configuration for wlan0 in dhcpcd.conf..."
    sudo sed -i '/^interface wlan0$/,/^$/d' "$DHCPCD_FILE"
    echo "$DESIRED_BLOCK" | sudo tee -a "$DHCPCD_FILE" > /dev/null
  else
    echo "✅ Static IP configuration already matches. Skipping."
  fi
else
  echo "📄 Using NetworkManager for static IP configuration..."
  NM_FILE="/etc/NetworkManager/system-connections/wlan0.nmconnection"
  if [[ ! -f "$NM_FILE" ]]; then
    echo "❌ NetworkManager config for wlan0 not found. You may need to create it manually or use nmcli."
  else
    echo "ℹ️ Static IP configuration via NetworkManager is not yet automated in this script."
  fi
fi

### 4b. Disable power saving on wlan0
echo "🔌 Disabling power saving on wlan0..."

WLAN_CONF="/etc/NetworkManager/conf.d/wifi-powersave-off.conf"
DESIRED_WLAN_CONF=$(cat <<EOF
[connection]
wifi.powersave = 2
EOF
)

if [[ ! -f "$WLAN_CONF" || "$(cat "$WLAN_CONF")" != "$DESIRED_WLAN_CONF" ]]; then
  echo "🔧 Writing power save config to $WLAN_CONF..."
  echo "$DESIRED_WLAN_CONF" | sudo tee "$WLAN_CONF" > /dev/null
  sudo systemctl restart NetworkManager
else
  echo "✅ Power saving already disabled on wlan0. Skipping."
fi

### 5. Install required packages directly
echo "📦 Checking and installing required packages..."

REQUIRED_PACKAGES=(
  python3-pip
  git
  i2c-tools
  libpq-dev
  postgresql
  rpi-connect
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" > /dev/null 2>&1; then
    echo "📦 Installing $pkg..."
    sudo apt-get install -y "$pkg"
  else
    echo "✅ $pkg already installed. Skipping."
  fi
done

### 6. Reboot
echo "🎉 Provisioning complete for $NEW_HOSTNAME. Rebooting..."
sudo reboot