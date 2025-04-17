#!/bin/sh

# Установим необходимые утилиты
apk update
apk add bash sudo shadow wget curl build-base linux-headers \
    openssl-dev readline-dev zlib-dev libxml2-dev libxslt-dev \
    libedit-dev bison flex tar iproute2 coreutils util-linux grep \
    procps pciutils ethtool bind-tools

# Создаём пользователя
adduser -D dbuser
echo "dbuser:password" | chpasswd

# Создаём каталоги
mkdir -p /usr/local/src && cd /usr/local/src

# Скачиваем и распаковываем PostgreSQL
wget https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz
tar -xzf postgresql-15.3.tar.gz
cd postgresql-15.3

# Сборка PostgreSQL
./configure --prefix=/usr/local/pgsql
make
make install

# Создаём каталог данных
mkdir -p /home/dbuser/pgdata
chown -R dbuser:dbuser /home/dbuser/pgdata
chown -R dbuser:dbuser /usr/local/pgsql

# Добавляем PostgreSQL в PATH и делаем инициализацию
echo 'export PATH=$PATH:/usr/local/pgsql/bin' >> /home/dbuser/.profile
su - dbuser -c "/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata"

# Запуск PostgreSQL-сервера
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start"
sleep 3

# Создание пользователя myuser
su - dbuser -c "/usr/local/pgsql/bin/createuser -P -e myuser"
# Пароль: password

# Создание БД
su - dbuser -c "/usr/local/pgsql/bin/createdb -O myuser mydb"

# Разрешаем подключения по сети
echo "host all all 0.0.0.0/0 md5" >> /home/dbuser/pgdata/pg_hba.conf
echo "listen_addresses = '*'" >> /home/dbuser/pgdata/postgresql.conf
su - dbuser -c "/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata restart"

# Получаем информацию об оборудовании
CPU=$(lscpu | grep "MHz" | awk '{print $3}')
RAM=$(free -m | grep Mem | awk '{print $2}')
DISK=$(df -h | grep '/$' | awk '{print $2}')
echo "CPU MHz: $CPU\nRAM MB: $RAM\nDisk Size: $DISK" > /home/dbuser/hardware.txt

# Сеть
INTERFACES=$(ip link | grep ": " | wc -l)
IP_INFO=$(ip a | grep inet | awk '{print $2}')
MAC_INFO=$(ip link | grep link/ether | awk '{print $2}')
GATEWAY=$(ip route | grep default | awk '{print $3}')
DNS=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')

# Пропускная способность (может не работать в виртуалке — зависит от окружения)
SPEEDS=""
for iface in $(ls /sys/class/net/); do
  SPEED=$(ethtool $iface 2>/dev/null | grep "Speed:" | awk '{print $2}')
  SPEEDS="$SPEEDS\n$iface: $SPEED"
done

echo -e "Interfaces: $INTERFACES\nIP: $IP_INFO\nMAC: $MAC_INFO\nGateway: $GATEWAY\nDNS: $DNS\nSpeeds: $SPEEDS" > /home/dbuser/network.txt
