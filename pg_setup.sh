#!/bin/sh

# --- Установка и проверка зависимостей ---
echo "Настройка репозиториев и установка зависимостей..."
{
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.20/main" > /etc/apk/repositories
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.20/community" >> /etc/apk/repositories
    
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
        iproute2
} || { echo "ОШИБКА: Не удалось установить зависимости"; exit 1; }

# --- Создание пользователя dbuser ---
echo "Создание пользователя dbuser..."
if ! id -u dbuser >/dev/null 2>&1; then
    adduser -D dbuser -G wheel || { echo "ОШИБКА: Не удалось создать пользователя dbuser"; exit 1; }
    echo "dbuser:password" | chpasswd || { echo "ОШИБКА: Не удалось установить пароль"; exit 1; }
    echo "Пользователь dbuser создан"
else
    echo "Пользователь dbuser уже существует"
fi

# --- Установка PostgreSQL 15.3 ---
echo "Установка PostgreSQL 15.3..."
cd /home/dbuser || { echo "ОШИБКА: Не удалось перейти в /home/dbuser"; exit 1; }

# Скачивание
if [ ! -f postgresql-15.3.tar.gz ]; then
    echo "Скачивание postgresql-15.3.tar.gz..."
    curl -O https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz || \
    curl -O https://mirror.racket-lang.org/postgresql/postgresql-15.3.tar.gz || \
    { echo "ОШИБКА: Не удалось скачать PostgreSQL"; exit 1; }
fi

# Распаковка
if [ ! -d postgresql-15.3 ]; then
    echo "Распаковка архива..."
    tar -xzf postgresql-15.3.tar.gz || { echo "ОШИБКА: Не удалось распаковать архив"; exit 1; }
fi

# Компиляция
cd postgresql-15.3 || { echo "ОШИБКА: Директория postgresql-15.3 не найдена"; exit 1; }

echo "Конфигурация сборки..."
./configure --prefix=/usr/local/pgsql || { echo "ОШИБКА: Ошибка конфигурации"; exit 1; }

echo "Компиляция (это может занять время)..."
make || { echo "ОШИБКА: Ошибка компиляции"; exit 1; }

echo "Установка..."
make install || { echo "ОШИБКА: Ошибка установки"; exit 1; }

# --- Настройка PostgreSQL ---
echo "Настройка PostgreSQL..."
mkdir -p /home/dbuser/pgdata || { echo "ОШИБКА: Не удалось создать pgdata"; exit 1; }
chown dbuser:dbuser /home/dbuser/pgdata || { echo "ОШИБКА: Не удалось изменить владельца pgdata"; exit 1; }

# Инициализация БД
echo "Инициализация кластера..."
su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata" || { echo "ОШИБКА: Не удалось инициализировать кластер"; exit 1; }

# Конфигурация
echo "Настройка конфигурации..."
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf || { echo "ОШИБКА: Не удалось настроить postgresql.conf"; exit 1; }
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf || { echo "ОШИБКА: Не удалось настроить pg_hba.conf"; exit 1; }

# Запуск
echo "Запуск PostgreSQL..."
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/postgres.log start" || { echo "ОШИБКА: Не удалось запустить PostgreSQL"; exit 1; }

# Создание пользователя и БД
echo "Создание базы данных и пользователя..."
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb" || { echo "ОШИБКА: Не удалось создать БД"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"CREATE USER myuser WITH PASSWORD 'password' SUPERUSER LOGIN;\"" || { echo "ОШИБКА: Не удалось создать пользователя"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\"" || { echo "ОШИБКА: Не удалось назначить права"; exit 1; }

# --- Создание отчетов ---
echo "Создание отчетов о системе..."

# Аппаратные характеристики
echo "Создание hardware.txt..."
{
    echo "=== CPU Info ==="
    cat /proc/cpuinfo | grep -E 'model name|cpu MHz'
    echo "\n=== Memory Info ==="
    free -h
    echo "\n=== Disk Info ==="
    df -h | grep '/$'
} > /home/dbuser/hardware.txt || { echo "ОШИБКА: Не удалось создать hardware.txt"; exit 1; }

# Сетевые характеристики
echo "Создание network.txt..."
{
    echo "=== Network Interfaces ==="
    ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}'
    echo "\n=== IP Addresses ==="
    ip -o -f inet addr show | awk '{print $2, $4}'
    echo "\n=== MAC Addresses ==="
    ip link | awk '/ether/ {print $2}'
    echo "\n=== Default Gateway ==="
    ip route | grep default
    echo "\n=== DNS Servers ==="
    cat /etc/resolv.conf | grep nameserver
} > /home/dbuser/network.txt || { echo "ОШИБКА: Не удалось создать network.txt"; exit 1; }

# --- Завершение ---
echo "============================================"
echo "PostgreSQL 15.3 успешно установлен и настроен"
echo "Кластер БД: /home/dbuser/pgdata"
echo "Бинарные файлы: /usr/local/pgsql/bin"
echo "Логи: /home/dbuser/postgres.log"
echo "Отчеты:"
echo "  /home/dbuser/hardware.txt"
echo "  /home/dbuser/network.txt"
echo "Доступ к БД:"
echo "  Пользователь: myuser"
echo "  Пароль: password"
echo "  База данных: mydb"
echo "============================================"
