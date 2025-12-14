# otus_less9
Administrator Linux. Professional
Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в /etc/default).

#Мы создадим три файла: файл конфигурации, скрипт с логикой и unit-файл для systemd.
#1. Файл конфигурации
cat > /etc/default/log-monitor <<EOF
# /etc/default/log-monitor

# Полный путь к файлу лога
LOG_FILE="/var/log/syslog"

# Ключевое слово для поиска
KEYWORD="ERROR"
###

EOF

<img width="333" height="127" alt="image" src="https://github.com/user-attachments/assets/5ba4465d-5b37-4c2d-9a3a-6b0af4efb44f" />

2. Скрипт сервиса

cat > /usr/local/bin/log-monitor.sh <<EOF
#!/bin/bash
###
# Загружаем настройки. Если файла нет, выходим с ошибкой.
if [ -f /etc/default/log-monitor ]; then
    . /etc/default/log-monitor
else
    echo "Config file /etc/default/log-monitor not found"
    exit 1
fi

# Проверяем, что переменные заданы
if [ -z "$LOG_FILE" ] || [ -z "$KEYWORD" ]; then
    echo "Variables LOG_FILE or KEYWORD are not set"
    exit 1
fi

# Бесконечный цикл с задержкой 30 секунд
while true; do
    if [ -f "$LOG_FILE" ]; then
        # Ищем ключевое слово.
        # -q означает "тихий режим" (только код возврата)
        if grep -q "$KEYWORD" "$LOG_FILE"; then
            echo "ALERT: Ключевое слово '$KEYWORD' найдено в файле $LOG_FILE"
        fi
    else
        echo "File $LOG_FILE does not exist"
    fi
    
    sleep 30
done

EOF

chmod +x /usr/local/bin/log-monitor.sh

3. Unit-файл systemd

cat > /etc/systemd/system/log-monitor.service <<EOF
[Unit]
Description=Simple Log Monitor Service
After=network.target

[Service]
Type=simple
# Явно указываем загрузку переменных, чтобы они были доступны в окружении сервиса
EnvironmentFile=/etc/default/log-monitor
ExecStart=/usr/local/bin/log-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
###
EOF

systemctl daemon-reload
systemctl enable --now log-monitor

systemctl status log-monitor

<img width="858" height="301" alt="image" src="https://github.com/user-attachments/assets/3c64abc9-2d59-4939-96b8-721a90090754" />


Посмотреть вывод сервиса (нашел ли он ключевое слово) можно через журнал:
journalctl -u log-monitor -f


Для проверки ключевого слова, создадим файл nano /var/log/test.log и изменим настроики в файле конфигурации /etc/default/log-monitor
 
echo "Тестовая запись: тут произошло событие ERROR для проверки" | sudo tee -a /var/log/test.log


<img width="1068" height="244" alt="image" src="https://github.com/user-attachments/assets/542dac26-1aef-48ce-ac7a-b7a038ae2d57" />


Часть 2. Установка spawn-fcgi и создание unit-файла


Задача: переделать init-скрипт в systemd unit.
1. Установка пакетов:

apt update
apt install spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid -y

2. Создаем файл настроек:

mkdir -p /etc/spawn-fcgi
cat > /etc/spawn-fcgi/fcgi.conf <<EOF
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s \$SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
EOF

3. Создаем Unit-файл:

cat > /etc/systemd/system/spawn-fcgi.service <<EOF
[Unit]
Description=Spawn-fcgi startup service by Otus
After=network.target

[Service]
Type=simple
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/spawn-fcgi/fcgi.conf
ExecStart=/usr/bin/spawn-fcgi -n \$OPTIONS
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

4. Запуск и проверка:

systemctl daemon-reload
systemctl start spawn-fcgi
systemctl status spawn-fcgi

<img width="1090" height="279" alt="image" src="https://github.com/user-attachments/assets/3fe210c0-feaa-49d4-9816-5d630caf9538" />

Часть 3. Запуск нескольких инстансов Nginx
Доработать unit-файл Nginx (nginx.service) для запуска нескольких инстансов сервера с разными конфигурационными файлами одновременно.

1. Установка Nginx:

apt install nginx -y
# Остановим стандартный nginx, чтобы он не занимал 80 порт и не мешал
systemctl stop nginx
systemctl disable nginx

2. Создаем шаблонный Unit-файл nginx@.service:

cat > /etc/systemd/system/nginx@.service <<EOF
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx-%I.pid
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx-%I.conf -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx-%I.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

3. Создаем конфигурационные файлы:

Мы создадим два минимальных рабочих конфига (first и second), чтобы гарантировать запуск.
Конфиг 1 (Порт 9001):

cat > /etc/nginx/nginx-first.conf <<EOF
pid /run/nginx-first.pid;
events {
    worker_connections 768;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access-first.log;
    error_log /var/log/nginx/error-first.log;
    server {
        listen 9001;
        server_name localhost;
        root /var/www/html;
        index index.html;
    }
}
EOF

Конфиг 2 (Порт 9002):

cat > /etc/nginx/nginx-second.conf <<EOF
pid /run/nginx-second.pid;
events {
    worker_connections 768;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access-second.log;
    error_log /var/log/nginx/error-second.log;
    server {
        listen 9002;
        server_name localhost;
        root /var/www/html;
        index index.html;
    }
}
EOF

4. Запуск и проверка:
Bash

systemctl daemon-reload
systemctl start nginx@first
systemctl start nginx@second

<img width="1113" height="136" alt="image" src="https://github.com/user-attachments/assets/d367e3ef-5583-4067-b679-7366c008b09b" />


<img width="1126" height="329" alt="image" src="https://github.com/user-attachments/assets/6aa0bd6a-8274-4887-b28d-45287e706535" />


Автоматический скрипт (Всё в одном)

homework.sh







