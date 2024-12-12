#!/bin/bash

# Memastikan skrip dijalankan dengan hak akses root
if [[ $EUID -ne 0 ]]; then
    echo "Script ini harus dijalankan sebagai root!" 
    exit 1
fi

# 1. Menanyakan nama domain dari pengguna
echo "Masukkan nama domain yang ingin Anda konfigurasi (misal: example.com):"
read -p "Domain: " DOMAIN

# Memeriksa apakah domain sudah diinput
if [ -z "$DOMAIN" ]; then
    echo "Domain tidak boleh kosong!"
    exit 1
fi

# 2. Menginstal Apache2 dan MySQL
echo "Menginstal Apache2 dan MySQL..."
apt update
apt install -y apache2 mysql-server

# 3. Mengonfigurasi Apache2 Virtual Host untuk domain
echo "Membuat konfigurasi Virtual Host untuk domain $DOMAIN di Apache2..."
WEB_ROOT="/var/www/$DOMAIN"
APACHE_CONF_DIR="/etc/apache2/sites-available"

# Membuat direktori untuk domain
mkdir -p "$WEB_ROOT"
echo "<h1>Welcome to $DOMAIN</h1>" > "$WEB_ROOT/index.html"

# Membuat file konfigurasi Apache
CONF_FILE="${APACHE_CONF_DIR}/${DOMAIN}.conf"

cat <<EOF > "$CONF_FILE"
<VirtualHost *:80>
    ServerAdmin root@localhost
    ServerName $DOMAIN
    DocumentRoot $WEB_ROOT
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Mengaktifkan konfigurasi dan merestart Apache
a2ensite "${DOMAIN}.conf"
systemctl restart apache2
echo "Virtual Host untuk $DOMAIN telah dibuat dan Apache telah direstart."

# 4. Mengonfigurasi MySQL Database dan Pengguna
echo "Membuat database dan pengguna MySQL untuk domain $DOMAIN..."
read -s -p "Masukkan password root MySQL (bisa dikosongkan): " MYSQL_ROOT_PASS
echo

# Meminta nama database kustom
read -p "Masukkan nama database yang diinginkan: " MYSQL_DB
if [ -z "$MYSQL_DB" ]; then
    MYSQL_DB="${DOMAIN}_db"
    echo "Menggunakan nama database default: $MYSQL_DB"
fi

# Meminta nama pengguna kustom
read -p "Masukkan nama pengguna MySQL yang diinginkan: " MYSQL_USER
if [ -z "$MYSQL_USER" ]; then
    MYSQL_USER="${DOMAIN}_user"
    echo "Menggunakan nama pengguna default: $MYSQL_USER"
fi

# Generate password acak jika tidak diisi
read -s -p "Masukkan password untuk pengguna MySQL (kosongkan untuk generate otomatis): " MYSQL_PASS
echo
if [ -z "$MYSQL_PASS" ]; then
    MYSQL_PASS=$(openssl rand -base64 12)
    echo "Password yang digenerate: $MYSQL_PASS"
fi

# Mengatur database dan pengguna
if [ -z "$MYSQL_ROOT_PASS" ]; then
    mysql -e "CREATE DATABASE $MYSQL_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $MYSQL_DB.* TO '$MYSQL_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
else
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE $MYSQL_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASS';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $MYSQL_DB.* TO '$MYSQL_USER'@'localhost';"
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;"
fi

echo "Database '$MYSQL_DB' dan pengguna MySQL '$MYSQL_USER' telah dibuat."
echo "Menyimpan kredensial database ke file..."
echo "Database: $MYSQL_DB" > "$WEB_ROOT/db_credentials.txt"
echo "Username: $MYSQL_USER" >> "$WEB_ROOT/db_credentials.txt"
echo "Password: $MYSQL_PASS" >> "$WEB_ROOT/db_credentials.txt"
chmod 600 "$WEB_ROOT/db_credentials.txt"

# 5. Mengonfigurasi SSL dengan Let's Encrypt (Certbot)
echo "Mengonfigurasi SSL dengan Certbot untuk domain $DOMAIN..."
apt install -y certbot python3-certbot-apache

# Mendapatkan sertifikat SSL untuk domain
certbot --apache -d $DOMAIN

# 6. Menambahkan Entri ke /etc/hosts untuk pengujian lokal (jika domain belum diatur di DNS)
echo "Menambahkan entri ke /etc/hosts untuk pengujian lokal..."
if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "127.0.0.1 $DOMAIN" | tee -a /etc/hosts
    echo "Entri untuk $DOMAIN telah ditambahkan ke /etc/hosts."
else
    echo "Entri untuk $DOMAIN sudah ada di /etc/hosts."
fi

# 7. Memastikan pembaruan SSL otomatis berfungsi
echo "Memeriksa pembaruan SSL otomatis..."
certbot renew --dry-run

# 8. Restart Apache untuk memastikan semua konfigurasi diterapkan
systemctl restart apache2

# Menyelesaikan
echo "Instalasi dan konfigurasi selesai!"
echo "Apache2, MySQL, dan SSL untuk domain $DOMAIN telah berhasil dikonfigurasi."
echo "Kredensial database tersimpan di: $WEB_ROOT/db_credentials.txt"
