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
echo "📦 Running apt update..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y || echo "⚠️ apt update failed"

echo "📦 Upgrading packages non-interactively..."
sudo apt-get -y -o Dpkg::Options::="--force-confold" upgrade | tee /var/log/pi_upgrade.log || {
  echo "🔁 Retrying upgrade with --fix-missing..."
  sudo apt-get -y -o Dpkg::Options::="--force-confold" upgrade --fix-missing
}

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
STATIC_CONF=$(cat <<EOF
interface wlan0
static ip_address=$STATIC_IP/24
static routers=$ROUTER_IP
static domain_name_servers=$DNS_IP
EOF
)

if ! grep -q "interface wlan0" /etc/dhcpcd.conf; then
  echo "📄 Adding static IP config to dhcpcd.conf..."
  echo "$STATIC_CONF" | sudo tee -a /etc/dhcpcd.conf > /dev/null
else
  echo "✅ Static IP config already present. Skipping."
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
  i2c-tools
  rpi-connect
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" > /dev/null 2>&1; then
    echo "📦 Installing $pkg..."
    sudo apt-get install -y "$pkg" || {
      echo "🔁 Retrying $pkg install with --fix-missing..."
      sudo apt-get install -y "$pkg" --fix-missing
    }
  else
    echo "✅ $pkg already installed. Skipping."
  fi
done

### 🧪 Verify pip installation
if ! command -v pip3 &> /dev/null; then
  echo "⚠️ pip3 not found after installing python3-pip. Attempting manual bootstrap..."
  curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  sudo python3 get-pip.py
  rm get-pip.py
else
  echo "✅ pip3 is available."
fi

### 6. Reboot
echo "🎉 Provisioning complete for $NEW_HOSTNAME. Rebooting..."
sudo reboot