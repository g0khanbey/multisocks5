#!/bin/bash
set -euo pipefail

# --- Kullanıcı girdisi ---
read -p "Proxy için temel username gir (örnek: proxyuser): " BASE_USER
read -s -p "Proxy için parola gir: " BASE_PASS
echo
read -p "Başlanacak port (default 1080): " START_PORT_INPUT || true
START_PORT=${START_PORT_INPUT:-1080}

# --- Gereksinimler ---
echo "Gerekli paketleri güncelliyorum ve dante-server kuruyorum..."
sudo apt update -y
sudo apt install -y dante-server

# --- IP tespiti (global IPv4 adresleri) ---
mapfile -t IPS < <(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1)

if [ ${#IPS[@]} -eq 0 ]; then
  echo "Sistemde global IPv4 adresi bulunamadı. Çıkılıyor."
  exit 1
fi

echo "Bulunan IP adresleri:"
for ip in "${IPS[@]}"; do echo " - $ip"; done

# --- Hazırlık klasörleri ---
sudo mkdir -p /etc/danted-multi
sudo chown root:root /etc/danted-multi

PORT=$START_PORT
SERVICES=()

for idx in "${!IPS[@]}"; do
  IP="${IPS[$idx]}"
  # servis ve dosya isimleri için IP'yi sanitize et
  IP_SANITIZED="${IP//./-}"
  CONF="/etc/danted-multi/danted-${IP_SANITIZED}.conf"
  LOG="/var/log/danted-${IP_SANITIZED}.log"
  SERVICE_NAME="danted-${IP_SANITIZED}.service"
  INTERNAL_PORT="$PORT"

  echo "Oluşturuluyor: IP=$IP, port=$INTERNAL_PORT, conf=$CONF, service=$SERVICE_NAME"

  # config dosyası
  sudo bash -c "cat > $CONF <<EOF
logoutput: $LOG
internal: 0.0.0.0 port = $INTERNAL_PORT
external: $IP
method: username
socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF"

  sudo chmod 644 "$CONF"

  # log dosyasını oluştur
  sudo touch "$LOG"
  sudo chown root:root "$LOG"
  sudo chmod 644 "$LOG"

  # kullanıcı oluştur (her IP için farklı user: base-1, base-2 vs.)
  USERNAME="${BASE_USER}-$((idx+1))"
  if ! id -u "$USERNAME" >/dev/null 2>&1; then
    sudo useradd --system --shell /usr/sbin/nologin "$USERNAME" 2>/dev/null || true
  fi
  echo "${USERNAME}:${BASE_PASS}" | sudo chpasswd
  echo "  Kullanıcı oluşturuldu/şifrelendi: $USERNAME"

  # systemd service dosyası
  SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
  sudo bash -c "cat > $SERVICE_PATH <<EOF
[Unit]
Description=Dante SOCKS5 ($IP)
After=network.target

[Service]
ExecStart=/usr/sbin/danted -f $CONF
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF"
  sudo chmod 644 "$SERVICE_PATH"

  # firewall: ufw varsa aç
  if sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow "$INTERNAL_PORT"/tcp
  fi

  # iptables: ekle (tekrar eklemeyi kontrol et)
  if ! sudo iptables -C INPUT -p tcp --dport "$INTERNAL_PORT" -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp --dport "$INTERNAL_PORT" -j ACCEPT
  fi

  SERVICES+=("$SERVICE_NAME")
  PORT=$((PORT+1))
done

# --- systemd reload & başlatma ---
sudo systemctl daemon-reload

for svc in "${SERVICES[@]}"; do
  sudo systemctl enable --now "$svc"
  echo "Servis aktif: $svc -> $(sudo systemctl is-active "$svc")"
done

echo
echo "Tüm dante instance'ları başlatıldı."

# --- Test komutlarını göster ---
echo
echo "Her IP için test komutları (curl ile socks5h test):"
PORT=$START_PORT
for idx in "${!IPS[@]}"; do
  IP="${IPS[$idx]}"
  IP_SANITIZED="${IP//./-}"
  USERNAME="${BASE_USER}-$((idx+1))"
  echo
  echo "IP: $IP  -> proxy port: $PORT  user: $USERNAME"
  echo "Test (örnek): curl -x socks5h://${USERNAME}:${BASE_PASS}@${IP}:${PORT} https://ifconfig.me"
  PORT=$((PORT+1))
done

echo
echo "Notlar:"
echo "- Eğer tek bir kullanıcı adı/parola ile tüm IP'ler üzerinden aynı kimlik bilgisiyle bağlanmak istersen, kullanıcı oluşturma kısmını değiştir ve tek bir kullanıcı kullan."
echo "- Dante config'de daha sıkı erişim istiyorsan client/socks bloklarını IP bazlı sınırla."
echo "- Servis logları: /var/log/danted-<ip-sanitized>.log"
