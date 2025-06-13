#!/bin/bash
# Automated setup script for Raspberry Pi Image Control GUI
# Run this as root or with sudo on a fresh Raspberry Pi OS install

set -euo pipefail

# 1. Variables (customize before running)
APP_USER="mc-user"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/webgui"
UPLOAD_DIR="${APP_DIR}/uploads"
REPO_URL="git@github.com:saltyseadog99/lectern-display.git"
BRANCH="main"

# Access Point settings
SSID="lectern03"
PASSPHRASE="Daggerboard!"
CHANNEL=6

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
DHCPCD_CONF="/etc/dhcpcd.conf"
SERVICE_FILE="/etc/systemd/system/pi-image-gui.service"

# 2. Unblock Wi-Fi and bring up interface
apt update
apt install -y rfkill
rfkill unblock wifi
ip link set wlan0 up

# 3. Install required packages
apt install -y \
  python3 python3-venv python3-pip python3-flask python3-werkzeug python3-pillow \
  fbi git hostapd dnsmasq dhcpcd5 net-tools

# 4. Prepare application directory
mkdir -p "${UPLOAD_DIR}"
chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
chmod -R u+rwX "${APP_DIR}"

# 5. Deploy application code as mc-user
rm -rf "${APP_DIR}.tmp"
if [ ! -d "${APP_DIR}/.git" ]; then
  sudo -u "${APP_USER}" git clone --branch "${BRANCH}" "${REPO_URL}" "${APP_DIR}.tmp"
  rm -rf "${APP_DIR}"
  mv "${APP_DIR}.tmp" "${APP_DIR}"
  chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
else
  cd "${APP_DIR}"
  sudo -u "${APP_USER}" git pull origin "${BRANCH}"
fi

# 6. Configure hostapd
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

# 7. Configure dnsmasq (revert to default resolv.conf handling)
mv "${DNSMASQ_CONF}" "${DNSMASQ_CONF}.orig" || true
cat > "${DNSMASQ_CONF}" <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
dhcp-option=3,192.168.4.1
EOF

# 8. Leave resolv.conf to DHCP to populate
# (avoid manual DNS entries to allow dnsmasq to function)

# 9. Configure static IP (dhcpcd)
mv "${DHCPCD_CONF}" "${DHCPCD_CONF}.orig" || true
cat > "${DHCPCD_CONF}" <<EOF
interface wlan0
  static ip_address=192.168.4.1/24
  nohook wpa_supplicant
EOF

# 10. Create Flask service
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

# 11. Add hostapd override to prep interface
mkdir -p /etc/systemd/system/hostapd.service.d
cat > /etc/systemd/system/hostapd.service.d/override.conf <<EOF
[Unit]
Before=network.target

[Service]
ExecStartPre=/usr/sbin/rfkill unblock wifi
ExecStartPre=/sbin/ip link set wlan0 up
EOF

# 12. Reload, unmask, and enable services
systemctl unmask hostapd
services=(hostapd dnsmasq dhcpcd pi-image-gui.service)
for svc in "${services[@]}"; do
  systemctl enable --now "$svc" || true
done

# 13. Summary
echo
 echo "Setup complete. SSID '${SSID}', passphrase '${PASSPHRASE}'."
echo "GUI at http://192.168.4.1:8000/"
