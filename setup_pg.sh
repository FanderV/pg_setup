#!/bin/sh

set -e

# === 1. Создание пользователя dbuser ===
adduser -D dbuser
echo "dbuser:password" | chpasswd

# === 2. Отчеты о системе ===
mkdir -p /home/dbuser

# Hardware
{
  echo "--- CPU INFO ---"
  lscpu
  echo "--- MEMORY ---"
  free -h
  echo "--- DISK ---"
  df -h
} > /home/dbuser/hardware.txt

# Network
{
  echo "--- INTERFACES ---"
  ip addr show
  echo "--- LINK INFO ---"
  ip link show
  echo "--- ROUTES ---"
  ip route show
  echo "--- DNS ---"
  cat /etc/resolv.conf
} > /home/dbuser/network.txt

chown dbuser:dbuser /home/dbuser/*.txt

# === 3. Установка зависимостей ===
apk add build-base readline-dev zlib-dev libxml2-dev libxslt-dev openssl-dev wget sudo

# === 4. Скачивание и установка PostgreSQL 15.3 ===
cd /usr/local/src
wget https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz
tar -xzf postgresql-15.3.tar.gz
cd postgresql-15.3
./configure --prefix=/usr/local/pgsql
make
make install  # <- только это выполняется от root

# === 5. Настройка среды для dbuser ===
su - dbuser <<'EOF'

# Инициализация кластера
mkdir -p /home/dbuser/pgdata
/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata

# Настройка конфигов
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /home/dbuser/pgdata/postgresql.conf

# Запуск PostgreSQL
/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start

# Создание суперпользователя postgres (если нужно)
createuser -s postgres

# Ожидание сервера
sleep 2

# Создание пользователя и БД
psql -U postgres <<SQL
CREATE USER myuser WITH PASSWORD 'password' LOGIN;
CREATE DATABASE mydb OWNER myuser;
GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;
SQL

EOF

echo "✅ Установка завершена. PostgreSQL работает от пользователя dbuser."
