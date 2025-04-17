#!/bin/sh

# Обновление системы и установка необходимых пакетов
apk update && apk upgrade

apk add bash coreutils build-base linux-headers \
    curl wget tar xz \
    gcc musl-dev make \
    readline-dev zlib-dev openssl-dev \
    util-linux pciutils net-tools iproute2

# Создание пользователя dbuser
adduser -D dbuser
echo "dbuser:password" | chpasswd

# Загрузка и распаковка PostgreSQL 15.3
cd /root
wget https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz
tar -xzf postgresql-15.3.tar.gz
cd postgresql-15.3

# Сборка и установка
./configure --prefix=/usr/local/pgsql
make
make install

# Инициализация кластера
mkdir -p /home/dbuser/pgdata
chown -R dbuser /home/dbuser/pgdata
su - dbuser -c '/usr/local/pgsql/bin/initdb -D /home/dbuser/pgdata'

# Запуск PostgreSQL
su - dbuser -c '/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start'

# Создание нового пользователя myuser и БД mydb
sleep 5
su - dbuser -c "/usr/local/pgsql/bin/createuser -P -e -s myuser"
su - dbuser -c "/usr/local/pgsql/bin/createdb mydb -O myuser"

# Запись аппаратной информации
echo "CPU Info:" > /home/dbuser/hardware.txt
cat /proc/cpuinfo | grep 'model name' >> /home/dbuser/hardware.txt
echo "\nRAM Info:" >> /home/dbuser/hardware.txt
free -h >> /home/dbuser/hardware.txt
echo "\nDisk Info:" >> /home/dbuser/hardware.txt
df -h >> /home/dbuser/hardware.txt

# Запись сетевой информации
echo "Network Interfaces:" > /home/dbuser/network.txt
ip -o link show | awk -F': ' '{print $2}' >> /home/dbuser/network.txt
echo "\nBandwidth (ifconfig):" >> /home/dbuser/network.txt
for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
    ethtool $iface 2>/dev/null | grep -i speed >> /home/dbuser/network.txt
done
echo "\nIP Configuration:" >> /home/dbuser/network.txt
ip addr show >> /home/dbuser/network.txt
echo "\nGateway and DNS:" >> /home/dbuser/network.txt
ip route show default >> /home/dbuser/network.txt
cat /etc/resolv.conf >> /home/dbuser/network.txt
