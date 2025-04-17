#!/bin/sh

set -e

# === Установка необходимых пакетов ===
apk update
apk add --no-cache build-base curl linux-headers bash     readline-dev zlib-dev openssl-dev util-linux     libxml2-dev libxslt-dev wget git iproute2 iputils busybox-extras

# === Создание пользователя dbuser ===
adduser -D dbuser
echo "dbuser:password" | chpasswd

# === Сбор информации о системе ===
CPU=$(lscpu | grep 'MHz' | awk '{print $3}')
RAM=$(free -m | awk '/Mem:/ {print $2 " MB"}')
DISK=$(df -h | awk '$6=="/"{print $2}')

echo "CPU MHz: $CPU\nRAM: $RAM\nDisk Size: $DISK" > /home/dbuser/hardware.txt

# === Сбор сетевой информации ===
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | wc -l)
SPEEDS=$(for i in $(ls /sys/class/net); do ethtool $i 2>/dev/null | grep Speed; done | awk '{print $2}' | paste -sd ',')
IP=$(ip -o -4 addr show | awk '{print $2, $4}')
MAC=$(ip link | awk '/ether/ {print $2}')
GATEWAY=$(ip route | awk '/default/ {print $3}')
DNS=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | paste -sd ',')

echo "Interfaces: $INTERFACES\nSpeeds: $SPEEDS\nIP: $IP\nMAC: $MAC\nGateway: $GATEWAY\nDNS: $DNS" > /home/dbuser/network.txt

chown dbuser:dbuser /home/dbuser/*.txt

# === Скачивание и сборка PostgreSQL 15.3 ===
cd /usr/local/src
wget https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz
tar -xzf postgresql-15.3.tar.gz
cd postgresql-15.3
./configure --prefix=/usr/local/pgsql
make
make install

# === Обновление PATH ===
echo 'export PATH=$PATH:/usr/local/pgsql/bin' >> /etc/profile
source /etc/profile

# === Создание кластера и инициализация БД ===
mkdir -p /home/dbuser/pgdata
chown -R dbuser /home/dbuser/pgdata
sudo -u dbuser /usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata

# === Запуск сервера PostgreSQL ===
sudo -u dbuser /usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start

# === Настройка PostgreSQL: добавление пользователей ===
sudo -u dbuser /usr/local/pgsql/bin/createuser postgres --superuser
sudo -u dbuser /usr/local/pgsql/bin/psql -c "ALTER USER postgres WITH PASSWORD 'password';"

sudo -u dbuser /usr/local/pgsql/bin/createdb mydb
sudo -u dbuser /usr/local/pgsql/bin/createuser myuser
sudo -u dbuser /usr/local/pgsql/bin/psql -c "ALTER USER myuser WITH PASSWORD 'password';"
sudo -u dbuser /usr/local/pgsql/bin/psql -c "ALTER ROLE myuser WITH LOGIN;"

# === Настройка доступа по сети ===
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf

# Перезапуск сервера
sudo -u dbuser /usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata restart

# === Создание схем, таблиц и тестовых данных ===
cat <<EOF > /home/dbuser/script.sql
CREATE SCHEMA mytabs;
CREATE SCHEMA myviews;

SET search_path TO mytabs;

CREATE TABLE tab1 (
    id SERIAL PRIMARY KEY,
    name TEXT,
    income INTEGER
);

CREATE TABLE tab2 (
    id SERIAL PRIMARY KEY,
    name TEXT,
    birth_year INTEGER
);

CREATE TABLE tab3 (
    id SERIAL PRIMARY KEY,
    name TEXT,
    is_twin BOOLEAN
);

INSERT INTO tab1 (name, income) VALUES
('Иван', 30000), ('Пётр', 25000), ('Максим', 40000), ('Алексей', 22000),
('Фёдор', 18000), ('Кирилл', 50000), ('Георгий', 28000);

INSERT INTO tab2 (name, birth_year) VALUES
('Мария', 1980), ('Елена', 1975), ('Светлана', 1990), ('Ольга', 1985),
('Анна', 2000), ('Татьяна', 1965), ('Ирина', 1970);

INSERT INTO tab3 (name, is_twin) VALUES
('Андрей', true), ('Никита', false), ('Денис', true),
('Павел', false), ('Игорь', false), ('Дмитрий', true), ('Роман', false);

SET search_path TO myviews;

CREATE MATERIALIZED VIEW view1 AS SELECT * FROM mytabs.tab1 WHERE income < 30000;
CREATE MATERIALIZED VIEW view2 AS SELECT * FROM mytabs.tab3 WHERE is_twin = true;
CREATE MATERIALIZED VIEW view3 AS SELECT * FROM mytabs.tab2 WHERE birth_year < 1980;
CREATE MATERIALIZED VIEW view4 AS SELECT * FROM mytabs.tab2 WHERE birth_year < 1990;
CREATE MATERIALIZED VIEW view5 AS SELECT * FROM mytabs.tab1 WHERE income > 20000;
EOF

chown dbuser:dbuser /home/dbuser/script.sql
sudo -u dbuser /usr/local/pgsql/bin/psql -d mydb -U myuser -f /home/dbuser/script.sql

# === Резервное копирование ===
sudo -u dbuser /usr/local/pgsql/bin/pg_dump -U myuser -d mydb > /home/dbuser/backup.sql
