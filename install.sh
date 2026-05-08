#!/bin/bash

# --- Настройка стилей ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m'
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_NC='\033[0m'

clear
echo -e "${C_CYAN}    ____  _____ _        _ __   __"
echo "   |  _ \| ____| |      / \\ \ / /"
echo "   | |_) |  _| | |     / _ \\ V / "
echo "   |  _ <| |___| |___ / ___ \| |  "
echo "   |_| \_\_____|_____/_/   \_\_|  ${C_NC}"
echo -e "${C_PURPLE}  ✦ Universal Relay Config v4.9 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

# --- Блок 1: Идеология ---
echo -e "${C_WHITE}💡 ДЛЯ ЧЕГО ЭТОТ СКРИПТ?${C_NC}"
echo -e "В связи с инициативами по учету и ограничению зарубежного трафика в РФ,"
echo -e "этот скрипт превращает ваш российский сервер в невидимый транзитный шлюз."
echo -e "Ваш домашний провайдер будет видеть только ${C_GREEN}внутренний российский трафик${C_NC},"
echo -e "в то время как вы будете свободно выходить в интернет через Европу.\n"

if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}❌ Ошибка: Пожалуйста, запустите скрипт с правами root (sudo bash ...)${C_NC}"
  exit 1
fi

# --- Блок 2: Ввод и УМНЫЙ парсинг ---
echo -e "${C_WHITE}🔗 ДАННЫЕ ПОДКЛЮЧЕНИЯ${C_NC}"
echo -e "Вы можете вставить полную ссылку (${C_YELLOW}vless://...${C_NC}), либо просто адрес (${C_YELLOW}домен:порт${C_NC})"
read -p "Ввод: " L

HAS_LINK=false

if [[ "$L" == vless://* ]] || [[ "$L" == hy2://* ]] || [[ "$L" == hysteria2://* ]]; then
    HAS_LINK=true
    PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
    ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
    EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
    PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
    
    if [[ "$L" == *"?"* ]]; then PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1); else PARAMS=""; fi
    if [[ "$L" == *"#"* ]]; then NAME=$(echo $L | sed -E 's/.*#(.*)/\1/'); else NAME="Relay"; fi
    
    echo -e "${C_GREEN}✔ Распознана полная ссылка. Протокол: $PROTO | Порт: $PORT${C_NC}"

elif [[ "$L" == *":"* ]] && [[ ! "$L" == *"/"* ]]; then
    EU_HOST=$(echo "$L" | awk -F: '{print $1}')
    PORT=$(echo "$L" | awk -F: '{print $2}')
    echo -e "${C_GREEN}✔ Распознан прямой адрес. Порт: $PORT${C_NC}"

else
    EU_HOST="$L"
    echo -e "${C_YELLOW}⚠️ Порт не указан.${C_NC}"
    read -p "🚪 Введите ПОРТ для переадресации (например, 8443 или 443): " PORT
fi

if [[ $EU_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EU_IP=$EU_HOST
    echo -e "   Целевой IP: ${C_YELLOW}$EU_IP${C_NC}\n"
else
    echo -e "   ${C_YELLOW}🔍 Обнаружен домен ($EU_HOST). Вычисляем IP...${C_NC}"
    EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)
    
    if [ -z "$EU_IP" ]; then
        echo -e "${C_RED}❌ Ошибка: Не удалось определить IP-адрес для $EU_HOST. Проверьте правильность написания!${C_NC}"
        exit 1
    fi
    echo -e "   ${C_GREEN}✔ Реальный IP зарубежного сервера: $EU_IP${C_NC}\n"
fi

# --- Блок 3: Домен и маскировка ---
echo -e "${C_WHITE}🌐 НАСТРОЙКА ДОМЕНА И МАСКИРОВКИ${C_NC}"
echo -e "Скрипт автоматически установит Web-сервер (Nginx)."
echo -e "Если вы не укажете домен, при переходе по вашему IP откроется ${C_YELLOW}страница-заглушка${C_NC}."
echo -e "Для максимальной маскировки настоятельно рекомендуем привязать домен!"
echo -e "🎁 ${C_PURPLE}Лайфхак:${C_NC} Бесплатный домен можно зарегистрировать здесь: ${C_CYAN}https://freedns.afraid.org/${C_NC}\n"

read -p "Введите ваш домен (или просто нажмите Enter, если его нет): " DOMAIN

LOCAL_IP=$(curl -s ifconfig.me)
if [ -z "$DOMAIN" ]; then ENTRY="$LOCAL_IP"; else ENTRY="$DOMAIN"; fi

# --- Блок 4: Установка ---
echo -e "\n${C_YELLOW}⚙️ Настраиваем маршрутизацию (TCP и UDP)...${C_NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -F
iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE
iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE

echo -e "${C_YELLOW}🛡️ Устанавливаем маскировку (Nginx) и сохраняем правила...${C_NC}"
apt-get update -qq && apt-get install -y -qq nginx iptables-persistent > /dev/null

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>System Maintenance</title><style>body{background:#0f0f11;color:#e0e0e0;text-align:center;padding:10vh 20px;font-family:sans-serif;}h1{font-weight:300;color:#fff;}</style></head><body><h1>🛠 Node Status: Maintenance</h1><p>Scheduled backend upgrades in progress. HTTP traffic is temporarily suspended.</p><p><i>Sysadmin Department</i></p></body></html>
EOF
systemctl restart nginx > /dev/null 2>&1

# --- Блок 5: Финал ---
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}🎉 SUCCESS! Сервер успешно настроен.${C_NC}"
echo -e "================================================\n"

if [ "$HAS_LINK" = true ]; then
    # Кодируем спецсимволы для безопасной URL-ссылки: - это %2D, [ это %5B, ] это %5D
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    
    echo -e "${C_WHITE}👇 ВАША НОВАЯ ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ 👇${C_NC}"
    if [ -z "$PARAMS" ]; then
        echo -e "${C_GREEN}${PROTO}://${ID}@${ENTRY}:${PORT}#${NEW_NAME}${C_NC}"
    else
        echo -e "${C_GREEN}${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}${C_NC}"
    fi
    echo -e "\nСкопируйте эту ссылку и вставьте в ваше приложение."
else
    echo -e "${C_WHITE}👇 ВАШИ ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ 👇${C_NC}"
    echo -e "Адрес (Address): ${C_GREEN}${ENTRY}${C_NC}"
    echo -e "Порт (Port):     ${C_GREEN}${PORT}${C_NC}"
    echo -e "\nЗайдите в ваше приложение и вручную замените старый адрес на этот новый."
    echo -e "Рекомендуем добавить к названию профиля: ${C_YELLOW}-TUN[${LOCAL_IP}]${C_NC} для удобства."
fi
echo -e "Приятного пользования свободным интернетом! 😉\n"
