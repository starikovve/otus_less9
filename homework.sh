#!/bin/bash

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами root (sudo)"
  exit
fi

echo "=== Начало выполнения ДЗ ==="

echo "[1/3] Настройка log-monitor..."

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

# 2 Скрипт сервиса

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

#3. Unit-файл systemd

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


# --- ЧАСТЬ 2: Spawn-fcgi ---
echo "[2/3] Настройка spawn-fcgi..."
apt-get update -qq
apt-get install spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid -y -qq

mkdir -p /etc/spawn-fcgi
cat > /etc/spawn-fcgi/fcgi.conf <<EOF
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s \$SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
EOF

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

systemctl daemon-reload
systemctl start spawn-fcgi

# --- ЧАСТЬ 3: Nginx Multi-instance ---
echo "[3/3] Настройка Nginx multi-instance..."
apt-get install nginx -y -qq
systemctl stop nginx
systemctl disable nginx

# Шаблонный юнит
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

# Конфиг 1
cat > /etc/nginx/nginx-first.conf <<EOF
pid /run/nginx-first.pid;
events { worker_connections 768; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access-first.log;
    error_log /var/log/nginx/error-first.log;
    server {
        listen 9001;
        server_name localhost;
        root /var/www/html;
    }
}
EOF

# Конфиг 2
cat > /etc/nginx/nginx-second.conf <<EOF
pid /run/nginx-second.pid;
events { worker_connections 768; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access-second.log;
    error_log /var/log/nginx/error-second.log;
    server {
        listen 9002;
        server_name localhost;
        root /var/www/html;
    }
}
EOF

systemctl daemon-reload
systemctl start nginx@first
systemctl start nginx@second

echo "=== Готово! Проверяем результаты: ==="
echo "1. Watchlog (timer active?):"
systemctl is-active watchlog.timer
echo "2. Spawn-fcgi (active?):"
systemctl is-active spawn-fcgi
echo "3. Nginx Instances (ports 9001, 9002 listening?):"
ss -tnulp | grep nginx
