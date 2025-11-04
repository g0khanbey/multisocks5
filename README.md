# 🧱 Ubuntu için Multi-IP SOCKS5 Proxy Kurulum Scripti

Bu proje, Ubuntu üzerinde birden fazla IP adresi için otomatik olarak **SOCKS5 proxy sunucusu (Dante)** kurulumunu yapan bir bash script içerir.  
Her IP için ayrı port, ayrı kullanıcı ve ayrı systemd servisi oluşturulur.  
Otomatik olarak **IP tespiti, yapılandırma, firewall ayarları** ve **servis başlatma** işlemlerini yapar.

---

## 🧰 Gereksinimler

- **Ubuntu 18.04, 20.04, 22.04 veya 24.04**
- `sudo` yetkilerine sahip bir kullanıcı hesabı
- Sunucuda birden fazla **public IPv4 adresi** atanmış olmalı

---

## ⚙️ Kurulum

Terminalde aşağıdaki komutları çalıştırın:

```bash
wget https://raw.githubusercontent.com/g0khanbey/multisocks5/main/socks5.sh
sudo bash socks5.sh
