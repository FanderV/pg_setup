#!/bin/sh

# --- Авто-конвертация CRLF в LF ---
if file "$0" | grep -q CRLF; then
    echo "Обнаружен Windows-формат строк (CRLF) — конвертирую в UNIX (LF)..."
    apk add --no-cache dos2unix >/dev/null 2>&1
    dos2unix "$0"
    echo "Готово! Запускаю скрипт повторно..."
    exec sh "$0"
fi

# --- Создание пользователя dbuser ---
adduser -D dbuser
echo "dbuser:password" | chpasswd

# --- Установка зависимостей и загрузка исходников PostgreSQL 15.3 ---
apk update
apk add --no-cache build-base readline-dev zlib-dev openssl-dev curl sudo

cd /home/dbuser
curl -O https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz
tar -xzf postgresql-15.3.tar.gz
cd postgresql-15.3

./configure --prefix=/usr/local/pgsql
make
make install  # Выполняется от root, как по заданию

# --- Создание кластера и запуск PostgreSQL ---
mkdir -p /home/dbuser/pgdata
chown dbuser:dbuser /home/dbuser/pgdata
adduser dbuser wheel  # для sudo, если понадобится

su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata"
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l logfile start"

# --- Создание БД и пользователя myuser ---
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb"
su - dbuser -c \"/usr/local/pgsql/bin/psql -c \\\"CREATE USER myuser WITH PASSWORD 'password' LOGIN;\\\"\"
su - dbuser -c \"/usr/local/pgsql/bin/psql -c \\\"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\\\"\"

# --- Разрешение подключения с любого IP ---
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata restart"

# --- Аппаратные характеристики ---
echo "CPU Info:" > /home/dbuser/hardware.txt
lscpu | grep 'Model name\|CPU MHz' >> /home/dbuser/hardware.txt
echo "\nMemory Info:" >> /home/dbuser/hardware.txt
free -h >> /home/dbuser/hardware.txt
echo "\nDisk Info:" >> /home/dbuser/hardware.txt
df -h | grep '/$' >> /home/dbuser/hardware.txt

# --- Сетевые характеристики ---
echo "Network Interfaces:" > /home/dbuser/network.txt
ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' >> /home/dbuser/network.txt
echo "\nIP Addresses:" >> /home/dbuser/network.txt
ip -o -f inet addr show | awk '{print $2, $4}' >> /home/dbuser/network.txt
echo "\nMAC Addresses:" >> /home/dbuser/network.txt
ip link | awk '/ether/ {print $2}' >> /home/dbuser/network.txt
echo "\nDefault Gateway:" >> /home/dbuser/network.txt
ip route | grep default >> /home/dbuser/network.txt
echo "\nDNS Servers:" >> /home/dbuser/network.txt
cat /etc/resolv.conf | grep nameserver >> /home/dbuser/network.txt

# --- Готово ---
echo "Всё готово! PostgreSQL 15.3 установлен и запущен, отчёты сохранены."
