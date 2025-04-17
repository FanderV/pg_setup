#!/bin/sh

# --- Проверка и настройка репозиториев ---
echo "http://dl-cdn.alpinelinux.org/alpine/v3.20/main" > /etc/apk/repositories
echo "http://dl-cdn.alpinelinux.org/alpine/v3.20/community" >> /etc/apk/repositories

# --- Установка зависимостей с повторными попытками ---
for i in 1 2 3; do
    apk update && \
    apk add --no-cache \
        build-base \
        readline-dev \
        zlib-dev \
        openssl-dev \
        curl \
        sudo \
        tar \
        bash \
        util-linux \
        procps \
        iproute2 && break
    
    echo "Попытка $i не удалась, повторяем через 5 секунд..."
    sleep 5
done || { echo "Не удалось установить зависимости"; exit 1; }

# --- Создание пользователя dbuser ---
if ! id -u dbuser >/dev/null 2>&1; then
    adduser -D dbuser
    echo "dbuser:password" | chpasswd
fi

# --- Установка PostgreSQL 15.3 из исходников ---
cd /home/dbuser
if ! curl -O https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz; then
    echo "Пробуем альтернативный URL для загрузки PostgreSQL..."
    curl -O https://mirror.racket-lang.org/postgresql/postgresql-15.3.tar.gz || { echo "Failed to download PostgreSQL"; exit 1; }
fi

cd postgresql-15.3 || { echo "PostgreSQL directory not found"; exit 1; }

./configure --prefix=/usr/local/pgsql || { echo "Configure failed"; exit 1; }
make || { echo "Make failed"; exit 1; }
make install || { echo "Make install failed"; exit 1; }

# --- Инициализация кластера ---
mkdir -p /home/dbuser/pgdata
chown dbuser:dbuser /home/dbuser/pgdata

su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata" || { echo "initdb failed"; exit 1; }

# --- Настройка PostgreSQL ---
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf

# --- Запуск PostgreSQL ---
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l logfile start" || { echo "pg_ctl start failed"; exit 1; }

# --- Создание БД и пользователя ---
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb" || { echo "createdb failed"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"CREATE USER myuser WITH PASSWORD 'password' SUPERUSER LOGIN;\"" || { echo "create user failed"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\"" || { echo "grant privileges failed"; exit 1; }

# --- Создание отчетов ---
# Аппаратные характеристики
echo "CPU Info:" > /home/dbuser/hardware.txt
cat /proc/cpuinfo | grep 'model name\|cpu MHz' >> /home/dbuser/hardware.txt
echo "\nMemory Info:" >> /home/dbuser/hardware.txt
free -h >> /home/dbuser/hardware.txt
echo "\nDisk Info:" >> /home/dbuser/hardware.txt
df -h | grep '/$' >> /home/dbuser/hardware.txt

# Сетевые характеристики
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

# --- Завершение ---
echo "PostgreSQL 15.3 успешно установлен и настроен согласно всем требованиям!"
echo "Кластер находится в /home/dbuser/pgdata"
echo "Сервер установлен в /usr/local/pgsql"
echo "Отчеты сохранены в /home/dbuser/hardware.txt и /home/dbuser/network.txt"
echo "Пользователь myuser создан с правами администратора и доступом по сети"
