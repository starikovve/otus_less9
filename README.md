# otus_less9
Administrator Linux. Professional
Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в /etc/default).

Мы создадим три файла: файл конфигурации, скрипт с логикой и unit-файл для systemd.
1. Файл конфигурации
nano /etc/default/log-monitor

# /etc/default/log-monitor

# Полный путь к файлу лога
LOG_FILE="/var/log/syslog"

# Ключевое слово для поиска
KEYWORD="ERROR"

<img width="333" height="127" alt="image" src="https://github.com/user-attachments/assets/5ba4465d-5b37-4c2d-9a3a-6b0af4efb44f" />

2. Скрипт сервиса

nano /usr/local/bin/log-monitor.sh

#!/bin/bash

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


chmod +x /usr/local/bin/log-monitor.sh

3. Unit-файл systemd

nano /etc/systemd/system/log-monitor.service

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


systemctl daemon-reload
systemctl enable --now log-monitor

systemctl status log-monitor

<img width="858" height="301" alt="image" src="https://github.com/user-attachments/assets/3c64abc9-2d59-4939-96b8-721a90090754" />


Посмотреть вывод сервиса (нашел ли он ключевое слово) можно через журнал:
journalctl -u log-monitor -f


Для проверки ключевого слова, создадим файл nano /var/log/test.log и изменим настроики в файле конфигурации /etc/default/log-monitor
 
echo "Тестовая запись: тут произошло событие ERROR для проверки" | sudo tee -a /var/log/test.log


<img width="1068" height="244" alt="image" src="https://github.com/user-attachments/assets/542dac26-1aef-48ce-ac7a-b7a038ae2d57" />






