#!/bin/sh

# --- Установка оригинальных зависимостей ---
apk update && apk add --no-cache \
    build-base \
    readline-dev \
    zlib-dev \
    openssl-dev \
    curl \
    sudo \
    tar \
    bash || { echo "ОШИБКА: Установка зависимостей"; exit 1; }

# --- Создание пользователя ---
adduser -D dbuser || { echo "ОШИБКА: Создание пользователя"; exit 1; }
echo "dbuser:password" | chpasswd || { echo "ОШИБКА: Установка пароля"; exit 1; }

# --- Установка PostgreSQL ---
cd /home/dbuser || exit 1
[ ! -f postgresql-15.3.tar.gz ] && {
    curl -sO https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz || 
    { echo "ОШИБКА: Загрузка PostgreSQL"; exit 1; }
}

tar -xzf postgresql-15.3.tar.gz || { echo "ОШИБКА: Распаковка"; exit 1; }
cd postgresql-15.3 || exit 1

./configure --prefix=/usr/local/pgsql >/dev/null && \
make >/dev/null && \
make install >/dev/null || { echo "ОШИБКА: Сборка/установка"; exit 1; }

# --- Настройка PostgreSQL ---
mkdir -p /home/dbuser/pgdata || exit 1
chown dbuser:dbuser /home/dbuser/pgdata || exit 1

su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata" >/dev/null || { echo "ОШИБКА: Инициализация БД"; exit 1; }

echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf || exit 1
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf || exit 1

su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/postgres.log start" >/dev/null || { echo "ОШИБКА: Запуск PostgreSQL"; exit 1; }

# --- Создание БД и пользователя ---
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb" >/dev/null || { echo "ОШИБКА: Создание БД"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"CREATE USER myuser WITH PASSWORD 'password' SUPERUSER LOGIN;\"" >/dev/null || { echo "ОШИБКА: Создание пользователя"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\"" >/dev/null || { echo "ОШИБКА: Назначение прав"; exit 1; }

# --- Отчеты ---
echo "=== CPU ===" > /home/dbuser/hardware.txt
grep -E 'model name|cpu MHz' /proc/cpuinfo >> /home/dbuser/hardware.txt || exit 1
echo "\n=== Memory ===" >> /home/dbuser/hardware.txt
free -h >> /home/dbuser/hardware.txt || exit 1
echo "\n=== Disk ===" >> /home/dbuser/hardware.txt
df -h | grep '/$' >> /home/dbuser/hardware.txt || exit 1

echo "=== Interfaces ===" > /home/dbuser/network.txt
ip -o link | awk '{print $2}' | sed 's/://' >> /home/dbuser/network.txt || exit 1
echo "\n=== IP/MAC ===" >> /home/dbuser/network.txt
ip -o -br a >> /home/dbuser/network.txt || exit 1
echo "\n=== Gateway ===" >> /home/dbuser/network.txt
ip r | grep default >> /home/dbuser/network.txt || exit 1

echo "Установка завершена успешно!"
