#!/bin/bash

# --- Настройка стилей ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m'
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_NC='\033[0m'

# --- Функция анимации (Спиннер) ---
spinner() {
    local pid=$!
    local delay=0.15
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    while kill -0 $pid 2>/dev/null; do
        for frame in "${frames[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then break; fi
            printf "\r  ${C_CYAN}%s${C_NC} Выполняется..." "$frame"
            sleep $delay
        done
    done
    printf "\r  ${C_GREEN}✔ Успешно завершено!                 ${C_NC}\n"
}

clear
printf "${C_CYAN}"
cat << 'EOF'
    ____  _____ _        _ __   __
   |  _ \| ____| |      / \ \ / /
   | |_) |  _| | |     / _ \ V / 
   |  _ <| |___| |___ / ___ \| |  
   |_| \_\_____|_____/_/   \_\_|  
EOF
printf "${C_NC}"
echo -e "${C_PURPLE}  ✦ Super Relay Wizard v5.3 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

# --- ШАГ 0: ВВЕДЕНИЕ И ПРЕДУПРЕЖДЕНИЕ ---
echo -e "${C_WHITE}💡 ДЛЯ ЧЕГО ЭТОТ СКРИПТ?${C_NC}"
echo -e "Этот мастер настройки превратит ваш сервер в невидимый транзитный шлюз."
echo -e "Ваш провайдер будет видеть только ${C_GREEN}внутренний российский трафик${C_NC},"
echo -e "а вы будете свободно выходить в интернет через ваш зарубежный сервер.\n"

echo -e "${C_YELLOW}⚠️ ВАЖНОЕ УСЛОВИЕ ДЛЯ ПРАВИЛЬНОГО БИЛЛИНГА:${C_NC}"
echo -e "Чтобы ваш домашний или мобильный провайдер не считал этот трафик зарубежным,"
echo -e "данная настройка ${C_RED}ОБЯЗАТЕЛЬНО${C_NC} должна производиться на сервере с ${C_GREEN}РОССИЙСКИМ IP${C_NC}."
echo -e "Убедитесь, что вы запустили скрипт на сервере, арендованном в РФ (Яндекс и т.д.).\n"

if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}❌ Ошибка: Запустите скрипт от имени администратора (sudo bash ...)${C_NC}"
  exit 1
fi

HAS_LINK=false

# --- ШАГ 1: МЕНЮ ВВОДА ---
echo -e "${C_WHITE}📌 ШАГ 1: ГДЕ ВАШИ ДАННЫЕ ОТ ЗАРУБЕЖНОГО VPN?${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} У меня есть полная ссылка (vless:// или hy2://)"
echo -e "  ${C_CYAN}2)${C_NC} У меня есть адрес и порт (например: server.vpn.com:8443)"
echo -e "  ${C_CYAN}3)${C_NC} Ввести IP-адрес и порт вручную по отдельности\n"

read -p "$(echo -e "👉 Выберите вариант ${C_YELLOW}[1, 2 или 3]${C_NC}: ")" STEP1_CHOICE
echo ""

case $STEP1_CHOICE in
    1)
        echo -e "${C_PURPLE}Вставьте вашу ссылку:${C_NC}"
        read -p "Ввод: " L
        if [[ "$L" == vless://* ]] || [[ "$L" == hy2://* ]] || [[ "$L" == hysteria2://* ]]; then
            HAS_LINK=true
            PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
            ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
            EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
            PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
            if [[ "$L" == *"?"* ]]; then PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1); else PARAMS=""; fi
            if [[ "$L" == *"#"* ]]; then NAME=$(echo $L | sed -E 's/.*#(.*)/\1/'); else NAME="Relay"; fi
            echo -e " ${C_GREEN}✔ Ссылка успешно расшифрована!${C_NC}"
        else
            echo -e "${C_RED}❌ Ошибка: Ссылка должна начинаться с vless:// или hy2://${C_NC}"
            exit 1
        fi
        ;;
    2)
        echo -e "${C_PURPLE}Введите адрес и порт через двоеточие:${C_NC}"
        read -p "Ввод: " L
        if [[ "$L" == *":"* ]] && [[ ! "$L" == *"/"* ]]; then
            EU_HOST=$(echo "$L" | awk -F: '{print $1}')
            PORT=$(echo "$L" | awk -F: '{print $2}')
            echo -e " ${C_GREEN}✔ Адрес и порт распознаны!${C_NC}"
        else
            echo -e "${C_RED}❌ Ошибка: Неверный формат. Нужно ввести домен:порт${C_NC}"
            exit 1
        fi
        ;;
    3)
        echo -e "${C_PURPLE}Введите данные вашего зарубежного сервера:${C_NC}"
        read -p "🌍 IP-адрес или домен: " EU_HOST
        read -p "🚪 ПОРТ: " PORT
        echo -e " ${C_GREEN}✔ Данные приняты!${C_NC}"
        ;;
    *)
        echo -e "${C_RED}❌ Ошибка: Выберите 1, 2 или 3.${C_NC}"
        exit 1
        ;;
esac

echo ""
if [[ $EU_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EU_IP=$EU_HOST
    echo -e "🎯 Целевой IP: ${C_YELLOW}$EU_IP${C_NC} (Порт: $PORT)\n"
else
    echo -e "🔍 Анализируем домен ($EU_HOST)..."
    EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)
    if [ -z "$EU_IP" ]; then
        echo -e "${C_RED}❌ Ошибка: Не удалось определить IP для $EU_HOST.${C_NC}"
        exit 1
    fi
    echo -e "🎯 Целевой IP найден: ${C_YELLOW}$EU_IP${C_NC} (Порт: $PORT)\n"
fi

# --- ШАГ 2: ДОМЕН ---
echo -e "${C_WHITE}📌 ШАГ 2: НАСТРОЙКА ВХОДНОГО ДОМЕНА${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} У меня ЕСТЬ домен для этого российского сервера"
echo -e "  ${C_CYAN}2)${C_NC} У меня НЕТ домена (использовать просто IP)\n"

read -p "$(echo -e "👉 Выберите вариант ${C_YELLOW}[1 или 2]${C_NC}: ")" STEP2_CHOICE
echo ""

LOCAL_IP=$(curl -s ifconfig.me)

if [ "$STEP2_CHOICE" == "1" ]; then
    read -p "Введите ваш домен: " DOMAIN
    ENTRY="$DOMAIN"
    echo -e " ${C_GREEN}✔ Ваш входной адрес: $ENTRY${C_NC}\n"
else
    ENTRY="$LOCAL_IP"
    echo -e " ${C_YELLOW}⚠️ Будет использован IP: $ENTRY${C_NC}\n"
fi

# --- ШАГ 3: РЕЖИМ УСТАНОВКИ ---
echo -e "${C_WHITE}📌 ШАГ 3: РЕЖИМ МАРШРУТИЗАЦИИ${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} 🧹 ОЧИСТИТЬ старые настройки и настроить всё с нуля"
echo -e "  ${C_CYAN}2)${C_NC} ➕ ДОБАВИТЬ этот порт к уже существующим (для второго протокола)\n"

read -p "$(echo -e "👉 Выберите вариант ${C_YELLOW}[1 или 2]${C_NC}: ")" STEP3_CHOICE
echo ""

# --- ШАГ 4: УСТАНОВКА (С АНИМАЦИЕЙ) ---
echo -e "${C_WHITE}📌 ШАГ 4: АВТОМАТИЧЕСКАЯ НАСТРОЙКА СИСТЕМЫ${C_NC}"

echo -e "⚙️ Настраиваем ядро и маршрутизацию трафика..."
(
    echo 1 > /proc/sys/net/ipv4/ip_forward

    if [ "$STEP3_CHOICE" == "1" ]; then
        iptables -t nat -F
    fi

    iptables -t nat -D PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
    iptables -t nat -D POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
    iptables -t nat -D POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null

    iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
    iptables -t nat -A POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE
    iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
    iptables -t nat -A POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE
) > /dev/null 2>&1 &
spinner

echo -e "🛡️ Проверяем и устанавливаем Web-сервер (Nginx) для маскировки..."
(
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx iptables-persistent
    
    cat <<EOF > /var/www/html/index.html
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>System Maintenance</title><style>body{background:#0f0f11;color:#e0e0e0;text-align:center;padding:10vh 20px;font-family:sans-serif;}h1{font-weight:300;color:#fff;}</style></head><body><h1>🛠 Node Status: Maintenance</h1><p>Scheduled backend upgrades in progress. HTTP traffic is temporarily suspended.</p><p><i>Sysadmin Department</i></p></body></html>
EOF
    systemctl restart nginx
    netfilter-persistent save
) > /dev/null 2>&1 &
spinner

# --- ФИНАЛ ---
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}🎉 ГОТОВО! ПОРТ $PORT УСПЕШНО ПРОБРОШЕН.${C_NC}"
echo -e "================================================\n"

if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    echo -e "${C_WHITE}👇 ВАША НОВАЯ ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ 👇${C_NC}"
    if [ -z "$PARAMS" ]; then
        echo -e "${C_GREEN}${PROTO}://${ID}@${ENTRY}:${PORT}#${NEW_NAME}${C_NC}"
    else
        echo -e "${C_GREEN}${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}${C_NC}"
    fi
else
    echo -e "${C_WHITE}👇 ВАШИ ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ 👇${C_NC}"
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC}"
    echo -e "Порт:  ${C_GREEN}${PORT}${C_NC}"
fi
echo -e "\nПриятного пользования свободным интернетом! 😉\n"
