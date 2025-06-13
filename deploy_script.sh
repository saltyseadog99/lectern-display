#!/bin/bash
# Automated setup script for Raspberry Pi Image Control GUI
# Run this as root or with sudo on a fresh Raspberry Pi OS install

set -euo pipefail

# 1. Variables (customize before running)
APP_USER="mc-user"                          # user to run the app under
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/webgui"
UPLOAD_DIR="${APP_DIR}/uploads"
REPO_URL="https://github.com/saltyseadog99/lectern-display.git"  # Your Git repository URL
BRANCH="main"

# Access Point settings
SSID="lectern03"
PASSPHRASE="Daggerboard!"
CHANNEL=6

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
DHCPCD_CONF="/etc/dhcpcd.conf"
SERVICE_FILE="/etc/systemd/system/pi-image-gui.service"

# 2. Ensure Wi-Fi is unblocked and interface is up
apt install -y rfkill
rfkill unblock wifi
ip link set wlan0 up

# 3. Configure networking services before package fetch
systemctl daemon-reload
systemctl restart hostapd dnsmasq dhcpcd

# 4. Install required packages
apt update
apt install -y \
  python3 python3-venv python3-pip python3-flask python3-werkzeug python3-pillow \
  fbi git

# 5. Install optional packages
apt install -y dnsmasq hostapd dhcpcd5 net-tools

# 6. Create application directory and uploads folder
mkdir -p "${UPLOAD_DIR}"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
chmod -R u+rwX "${APP_DIR}"

# 7. Deploy application code with Git initialization
if [ -n "${REPO_URL}" ]; then
  rm -rf "${APP_DIR}.tmp"
  if [ ! -d "${APP_DIR}/.git" ]; then
    git clone --branch "${BRANCH}" "${REPO_URL}" "${APP_DIR}.tmp"
    rm -rf "${APP_DIR}"
    mv "${APP_DIR}.tmp" "${APP_DIR}"
    chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
  else
    cd "${APP_DIR}"
    sudo -u "${APP_USER}" git pull origin "${BRANCH}"
  fi
else
  echo "Note: No REPO_URL set; ensure app.py and uploads/ are in ${APP_DIR}"
fi

# 8. Configure hostapd (Access Point)
cat > "${HOSTAPD_CONF}" <<EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# 9. Configure dnsmasq (DHCP)
mv "${DNSMASQ_CONF}" "${DNSMASQ_CONF}.orig" || true
cat > "${DNSMASQ_CONF}" <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
dhcp-option=3,192.168.4.1
EOF

# 10. Configure static IP (dhcpcd)
mv "${DHCPCD_CONF}" "${DHCPCD_CONF}.orig" || true
cat > "${DHCPCD_CONF}" <<EOF
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
EOF

# 11. Create systemd service for the Flask app
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Pi Image Upload & Display GUI
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 12. Create hostapd override to unblock Wi-Fi and bring up WLAN
mkdir -p /etc/systemd/system/hostapd.service.d
cat > /etc/systemd/system/hostapd.service.d/override.conf <<EOF
[Unit]
Before=network.target

[Service]
ExecStartPre=/usr/sbin/rfkill unblock wifi
ExecStartPre=/sbin/ip link set wlan0 up
EOF

# 13. Reload systemd and enable services
systemctl unmask hostapd
enable_services=(hostapd dnsmasq dhcpcd pi-image-gui.service)
for svc in "${enable_services[@]}"; do systemctl enable --now "$svc"; done

# 14. Summary
echo
echo "Installation complete."
echo "Connect to Wi-Fi SSID '${SSID}' with password '${PASSPHRASE}'."
echo "Then browse to http://192.168.4.1:8000/ to access the GUI."
