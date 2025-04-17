#!/bin/bash

# Запуск PostgreSQL
/usr/local/pgsql/bin/pg_ctl -D /home/dbuser/pgdata -l /home/dbuser/logfile start

# Подключение к базе данных mydb под пользователем myuser
/usr/local/pgsql/bin/psql -U myuser -d mydb -h localhost << EOF

-- Создание схем
CREATE SCHEMA IF NOT EXISTS mytabs;
CREATE SCHEMA IF NOT EXISTS myviews;

-- Таблица tab1: мужья
CREATE TABLE mytabs.tab1 (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    middle_name VARCHAR(50),
    last_name VARCHAR(50),
    birth_year INT,
    gender CHAR(1) DEFAULT 'M',
    monthly_income NUMERIC(10,2)
);

-- Таблица tab2: жены
CREATE TABLE mytabs.tab2 (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    middle_name VARCHAR(50),
    last_name VARCHAR(50),
    birth_year INT,
    gender CHAR(1) DEFAULT 'F',
    monthly_income NUMERIC(10,2)
);

-- Таблица tab3: дети
CREATE TABLE mytabs.tab3 (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    middle_name VARCHAR(50),
    last_name VARCHAR(50),
    birth_year INT,
    gender CHAR(1),
    monthly_income NUMERIC(10,2),
    twin BOOLEAN DEFAULT FALSE,
    father_id INT REFERENCES mytabs.tab1(id),
    mother_id INT REFERENCES mytabs.tab2(id)
);

-- Наполнение таблиц
INSERT INTO mytabs.tab1 (first_name, middle_name, last_name, birth_year, monthly_income) VALUES
('Иван', 'Петрович', 'Сидоров', 1980, 50000),
('Алексей', 'Игоревич', 'Миронов', 1978, 40000),
('Сергей', 'Викторович', 'Кузнецов', 1985, 30000),
('Михаил', 'Сергеевич', 'Иванов', 1990, 60000),
('Николай', 'Андреевич', 'Павлов', 1982, 45000),
('Петр', 'Егорович', 'Смирнов', 1988, 70000),
('Анатолий', 'Олегович', 'Лебедев', 1975, 32000);

INSERT INTO mytabs.tab2 (first_name, middle_name, last_name, birth_year, monthly_income) VALUES
('Мария', 'Ивановна', 'Сидорова', 1982, 30000),
('Елена', 'Павловна', 'Миронова', 1980, 45000),
('Анна', 'Сергеевна', 'Кузнецова', 1987, 25000),
('Ольга', 'Михайловна', 'Иванова', 1992, 62000),
('Татьяна', 'Николаевна', 'Павлова', 1984, 40000),
('Ирина', 'Петровна', 'Смирнова', 1990, 65000),
('Светлана', 'Анатольевна', 'Лебедева', 1976, 31000);

INSERT INTO mytabs.tab3 (first_name, middle_name, last_name, birth_year, gender, monthly_income, twin, father_id, mother_id) VALUES
('Виктор', 'Иванович', 'Сидоров', 2005, 'M', 5000, FALSE, 1, 1),
('Анна', 'Ивановна', 'Сидорова', 2005, 'F', 0, TRUE, 1, 1),
('Павел', 'Алексеевич', 'Миронов', 2007, 'M', 3000, FALSE, 2, 2),
('Екатерина', 'Сергеевна', 'Кузнецова', 2010, 'F', 0, FALSE, 3, 3),
('Игорь', 'Михайлович', 'Иванов', 2009, 'M', 0, TRUE, 4, 4),
('Ирина', 'Николаевна', 'Павлова', 2011, 'F', 2000, FALSE, 5, 5),
('Максим', 'Петрович', 'Смирнов', 2008, 'M', 1500, TRUE, 6, 6);

-- 1. Проверка существования человека по ФИО
CREATE MATERIALIZED VIEW myviews.view1 AS
SELECT first_name, middle_name, last_name FROM mytabs.tab1
UNION
SELECT first_name, middle_name, last_name FROM mytabs.tab2
UNION
SELECT first_name, middle_name, last_name FROM mytabs.tab3;

-- 2. Все работающие дети
CREATE MATERIALIZED VIEW myviews.view2 AS
SELECT
    id,
    first_name,
    middle_name,
    last_name,
    birth_year,
    gender,
    monthly_income,
    twin,
    father_id,
    mother_id
FROM mytabs.tab3
WHERE monthly_income > 0;

-- 3. Мужья с доходом выше жены
CREATE MATERIALIZED VIEW myviews.view3 AS
SELECT
    m.first_name AS husband_name,
    w.first_name AS wife_name,
    m.monthly_income AS husband_income,
    w.monthly_income AS wife_income
FROM mytabs.tab1 m
JOIN mytabs.tab2 w ON m.id = w.id
WHERE m.monthly_income > w.monthly_income;

-- 4. Люди без дохода, родившиеся до 1990 года
CREATE MATERIALIZED VIEW myviews.view4 AS
SELECT first_name, last_name, birth_year, monthly_income FROM mytabs.tab1
WHERE monthly_income = 0 AND birth_year < 1990
UNION ALL
SELECT first_name, last_name, birth_year, monthly_income FROM mytabs.tab2
WHERE monthly_income = 0 AND birth_year < 1990
UNION ALL
SELECT first_name, last_name, birth_year, monthly_income FROM mytabs.tab3
WHERE monthly_income = 0 AND birth_year < 1990;

-- 5. Число семей с близнецами
CREATE MATERIALIZED VIEW myviews.view5 AS
SELECT COUNT(DISTINCT father_id) AS families_with_twins
FROM mytabs.tab3
WHERE twin = TRUE;



EOF

# Резервное копирование базы данных
/usr/local/pgsql/bin/pg_dump -U myuser -h localhost -d mydb -F p -f /home/dbuser/backup.sql
