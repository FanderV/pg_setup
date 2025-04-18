#!/bin/bash

# Запуск PostgreSQL
/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start

# Подключение к базе данных mydb под пользователем myuser
/usr/local/pgsql/bin/psql -U myuser -d mydb -h localhost << EOF

код создания таблиц и тд.

# Резервное копирование базы данных
/usr/local/pgsql/bin/pg_dump -U myuser -h localhost -d mydb -F p -f /home/dbuser/backup.sql
