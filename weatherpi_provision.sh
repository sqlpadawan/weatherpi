#!/bin/bash
set -e

##chmod +x weatherpi_provision.sh
##sudo weatherpi_provision.sh \
##  weatherpi \
##  192.168.9.105 \
##  192.168.9.1 \
##  192.168.9.1 \
##  https://raw.githubusercontent.com/sqlpadawan/raspi_key/main/raspi_key.pub \
##  raspi

### 🧠 Parse arguments
NEW_HOSTNAME="$1"
STATIC_IP="$2"
ROUTER_IP="$3"
DNS_IP="$4"
SSH_KEY_URL="$5"
USERNAME="$6"

if [[ -z "$NEW_HOSTNAME" || -z "$STATIC_IP" || -z "$ROUTER_IP" || -z "$DNS_IP" || -z "$SSH_KEY_URL" || -z "$USERNAME" ]]; then
  echo "❌ Usage: $0 <hostname> <static_ip> <router_ip> <dns_ip> <ssh_key_url> <username>"
  exit 1
fi

echo "🔧 Starting Raspberry Pi provisioning for $NEW_HOSTNAME with user $USERNAME..."

USE_DHCPCD=false
if systemctl is-active --quiet dhcpcd; then
  USE_DHCPCD=true
fi

### 1. Update system
#sudo apt update && sudo apt upgrade -y
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
    # Optional: Add nmcli commands here to configure static IP
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

### 5. Install cloud-init
echo "☁️ Installing cloud-init..."
sudo apt install -y cloud-init cloud-guest-utils curl

sudo tee /etc/cloud/cloud.cfg.d/99_pi.cfg > /dev/null <<EOF
datasource_list: [ NoCloud ]
EOF

### 6. Fetch SSH key from Git
echo "🔑 Fetching SSH key from $SSH_KEY_URL..."
SSH_KEY=$(curl -fsSL "$SSH_KEY_URL")
if [[ -z "$SSH_KEY" ]]; then
  echo "❌ Failed to fetch SSH key from $SSH_KEY_URL"
  exit 1
fi

if ! echo "$SSH_KEY" | grep -Eq '^ssh-(rsa|ed25519) '; then
  echo "❌ Invalid SSH public key format"
  exit 1
fi

### 7. Conditionally seed cloud-init files
echo "📦 Checking cloud-init seed files..."
SEED_DIR="/var/lib/cloud/seed/nocloud-net"
USER_DATA_PATH="$SEED_DIR/user-data"
META_DATA_PATH="$SEED_DIR/meta-data"

mkdir -p "$SEED_DIR"

DESIRED_USER_DATA=$(cat <<EOF
#cloud-config
hostname: $NEW_HOSTNAME
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $SSH_KEY

package_update: true
packages:
  - python3-pip
  - git
  - i2c-tools
  - libpq-dev
  - postgresql

write_files:
  - path: /home/$USERNAME/log_aht20_data.py
    permissions: '0755'
    content: |
      #!/home/$USERNAME/weather_env/bin/python
      import time
      import board
      import adafruit_ahtx0
      import psycopg2
      sensor = adafruit_ahtx0.AHTx0(board.I2C())
      conn = psycopg2.connect("dbname=sensordb user=$USERNAME password=yourpassword")
      cur = conn.cursor()
      while True:
          temp = sensor.temperature
          hum = sensor.relative_humidity
          cur.execute("INSERT INTO readings (timestamp, temperature, humidity) VALUES (NOW(), %s, %s)", (temp, hum))
          conn.commit()
          time.sleep(60)

runcmd:
  - python3 -m pip install --upgrade pip virtualenv
  - if [ ! -d "/home/$USERNAME/weather_env" ]; then python3 -m virtualenv /home/$USERNAME/weather_env; fi
  - /home/$USERNAME/weather_env/bin/pip install --upgrade pip
  - if ! /home/$USERNAME/weather_env/bin/pip show adafruit-circuitpython-ahtx0 > /dev/null 2>&1; then
      /home/$USERNAME/weather_env/bin/pip install adafruit-circuitpython-ahtx0 adafruit-blinka psycopg2-binary;
    fi
  - chown -R $USERNAME:$USERNAME /home/$USERNAME/weather_env
  - chown $USERNAME:$USERNAME /home/$USERNAME/log_aht20_data.py
  - chmod +x /home/$USERNAME/log_aht20_data.py
  - if ! dpkg -s rpi-connect > /dev/null 2>&1; then
      apt update && apt install -y rpi-connect;
    fi
  - if ! dpkg -s nginx > /dev/null 2>&1; then
      apt update && apt install -y nginx;
      systemctl enable nginx;
      systemctl start nginx;
    fi
  - touch /home/$USERNAME/logger.log
  - chown $USERNAME:$USERNAME /home/$USERNAME/logger.log
  - CRON_LINE="# */10 * * * * /home/$USERNAME/weather_env/bin/python /home/$USERNAME/log_aht20_data.py >> /home/$USERNAME/logger.log 2>&1"
  - (crontab -u $USERNAME -l 2>/dev/null | grep -F "$CRON_LINE") || (crontab -u $USERNAME -l 2>/dev/null; echo "$CRON_LINE") | crontab -u $USERNAME -
EOF
)

DESIRED_META_DATA=$(cat <<EOF
instance-id: pi-instance
local-hostname: $NEW_HOSTNAME
EOF
)

USER_HASH_NEW=$(echo "$DESIRED_USER_DATA" | sha256sum | cut -d ' ' -f1)
META_HASH_NEW=$(echo "$DESIRED_META_DATA" | sha256sum | cut -d ' ' -f1)

USER_HASH_EXISTING=""
META_HASH_EXISTING=""

if [ -f "$USER_DATA_PATH" ]; then
  USER_HASH_EXISTING=$(sha256sum "$USER_DATA_PATH" | cut -d ' ' -f1)
fi
if [ -f "$META_DATA_PATH" ]; then
  META_HASH_EXISTING=$(sha256sum "$META_DATA_PATH" | cut -d ' ' -f1)
fi

if [[ "$USER_HASH_NEW" != "$USER_HASH_EXISTING" || "$META_HASH_NEW" != "$META_HASH_EXISTING" ]]; then
  echo "🔄 Updating cloud-init seed files..."
  echo "$DESIRED_USER_DATA" | sudo tee "$USER_DATA_PATH" > /dev/null
  echo "$DESIRED_META_DATA" | sudo tee "$META_DATA_PATH" > /dev/null
else
  echo "✅ Cloud-init seed files already match. Skipping."
fi

### 8. Trigger cloud-init
echo "🚀 Triggering cloud-init..."
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final

### 9. Optional cleanup
SCRIPT_PATH="/home/$USERNAME/pi_provision.sh"
if [ -f "$SCRIPT_PATH" ]; then
  echo "🧹 Cleaning up provisioning script..."
  sudo rm "$SCRIPT_PATH"
fi

echo "🎉 Provisioning complete for $NEW_HOSTNAME. Rebooting..."
sudo reboot