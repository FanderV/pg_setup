#!/bin/sh

# --- Установка всех необходимых зависимостей ---
echo "Установка зависимостей..."
apk update && apk add --no-cache \
    build-base \
    readline-dev \
    zlib-dev \
    openssl-dev \
    curl \
    sudo \
    tar \
    bash \
    linux-headers \
    musl-dev \
    bison \
    flex \
    perl \
    python3 \
    libxml2-dev \
    libxslt-dev \
    icu-dev \
    openssl \
    libedit-dev \
    libuuid \
    util-linux-dev || { echo "ОШИБКА: Не удалось установить зависимости"; exit 1; }

# --- Создание пользователя dbuser ---
echo "Создание пользователя dbuser..."
if ! id -u dbuser >/dev/null 2>&1; then
    adduser -D dbuser || { echo "ОШИБКА: Не удалось создать пользователя dbuser"; exit 1; }
    echo "dbuser:password" | chpasswd || { echo "ОШИБКА: Не удалось установить пароль"; exit 1; }
fi

# --- Установка PostgreSQL 15.3 из исходников ---
echo "Загрузка и установка PostgreSQL 15.3..."
cd /home/dbuser || { echo "ОШИБКА: Не удалось перейти в /home/dbuser"; exit 1; }

# Скачивание
if [ ! -f postgresql-15.3.tar.gz ]; then
    echo "Скачивание postgresql-15.3.tar.gz..."
    curl -sO https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz || 
    curl -sO https://mirror.racket-lang.org/postgresql/postgresql-15.3.tar.gz || 
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
./configure --prefix=/usr/local/pgsql \
            --with-openssl \
            --with-libxml \
            --with-libxslt \
            --with-icu \
            --with-uuid=e2fs >/dev/null || { echo "ОШИБКА: Ошибка конфигурации"; exit 1; }

echo "Компиляция (это может занять время)..."
make -j$(nproc) >/dev/null || { echo "ОШИБКА: Ошибка компиляции"; exit 1; }

echo "Установка..."
make install >/dev/null || { echo "ОШИБКА: Ошибка установки"; exit 1; }

# --- Настройка PostgreSQL ---
echo "Настройка PostgreSQL..."
mkdir -p /home/dbuser/pgdata || { echo "ОШИБКА: Не удалось создать pgdata"; exit 1; }
chown dbuser:dbuser /home/dbuser/pgdata || { echo "ОШИБКА: Не удалось изменить владельца pgdata"; exit 1; }

# Инициализация БД
echo "Инициализация кластера..."
su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata" >/dev/null || { echo "ОШИБКА: Не удалось инициализировать кластер"; exit 1; }

# Конфигурация
echo "Настройка конфигурации..."
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf || { echo "ОШИБКА: Не удалось настроить postgresql.conf"; exit 1; }
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf || { echo "ОШИБКА: Не удалось настроить pg_hba.conf"; exit 1; }

# Запуск
echo "Запуск PostgreSQL..."
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/postgres.log start" >/dev/null || { echo "ОШИБКА: Не удалось запустить PostgreSQL"; exit 1; }

# Создание пользователя и БД
echo "Создание базы данных и пользователя..."
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb" >/dev/null || { echo "ОШИБКА: Не удалось создать БД"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"CREATE USER myuser WITH PASSWORD 'password' SUPERUSER LOGIN;\"" >/dev/null || { echo "ОШИБКА: Не удалось создать пользователя"; exit 1; }
su - dbuser -c "/usr/local/pgsql/bin/psql -c \"GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;\"" >/dev/null || { echo "ОШИБКА: Не удалось назначить права"; exit 1; }

# --- Создание отчетов ---
echo "Создание отчетов о системе..."

# Аппаратные характеристики
echo "=== CPU Info ===" > /home/dbuser/hardware.txt
grep -E 'model name|cpu MHz' /proc/cpuinfo >> /home/dbuser/hardware.txt || exit 1
echo "\n=== Memory Info ===" >> /home/dbuser/hardware.txt
free -h >> /home/dbuser/hardware.txt || exit 1
echo "\n=== Disk Info ===" >> /home/dbuser/hardware.txt
df -h | grep '/$' >> /home/dbuser/hardware.txt || exit 1

# Сетевые характеристики
echo "=== Network Interfaces ===" > /home/dbuser/network.txt
ip -o link | awk '{print $2}' | sed 's/://' >> /home/dbuser/network.txt || exit 1
echo "\n=== IP Addresses ===" >> /home/dbuser/network.txt
ip -o -br a >> /home/dbuser/network.txt || exit 1
echo "\n=== MAC Addresses ===" >> /home/dbuser/network.txt
ip link | awk '/ether/ {print $2}' >> /home/dbuser/network.txt || exit 1
echo "\n=== Default Gateway ===" >> /home/dbuser/network.txt
ip route | grep default >> /home/dbuser/network.txt || exit 1
echo "\n=== DNS Servers ===" >> /home/dbuser/network.txt
cat /etc/resolv.conf | grep nameserver >> /home/dbuser/network.txt || exit 1

# --- Завершение ---
cat <<EOF

УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО
============================================
PostgreSQL 15.3 успешно установлен и настроен
Кластер БД: /home/dbuser/pgdata
Бинарные файлы: /usr/local/pgsql/bin
Логи: /home/dbuser/postgres.log

Доступ к БД:
  Хост: localhost
  Порт: 5432
  База данных: mydb
  Пользователь: myuser
  Пароль: password

Отчеты:
  /home/dbuser/hardware.txt - аппаратные характеристики
  /home/dbuser/network.txt - сетевые настройки

Для управления сервером:
  Запуск: /usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata start
  Остановка: /usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata stop
============================================
EOF
