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
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    while kill -0 $pid 2>/dev/null; do
        for frame in "${frames[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then break; fi
            printf "\r  ${C_CYAN}%s${C_NC} Выполняется..." "$frame"
            sleep 0.1
        done
    done
    printf "\r  ${C_GREEN}✔ Готово!                           ${C_NC}\n"
}

# --- Функция цикличного меню (Защита от дурака) ---
# Параметры: $1 - текст вопроса, $2 - количество вариантов
ask_step() {
    local attempts=0
    local max_attempts=5
    while true; do
        read -p "$(echo -e "$1")" choice
        if [[ "$choice" =~ ^[1-$2]$ ]]; then
            echo "$choice"
            return 0
        else
            ((attempts++))
            if [ $attempts -ge $max_attempts ]; then
                echo -e "\n${C_YELLOW}⚠️ Слишком много ошибок ($attempts).${C_NC}"
                read -p "Хотите продолжить (1) или выйти (2)? " retry
                if [ "$retry" == "2" ]; then
                    echo -e "${C_RED}Установка отменена. Всего доброго!${C_NC}"
                    exit 1
                fi
                attempts=0
            else
                echo -e "${C_RED}❌ Ошибка! Введите цифру от 1 до $2 (Попытка $attempts из $max_attempts)${C_NC}"
            fi
        fi
    done
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
echo -e "${C_PURPLE}  ✦ Super Relay Wizard v5.4 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

echo -e "${C_WHITE}💡 ДЛЯ ЧЕГО ЭТОТ СКРИПТ?${C_NC}"
echo -e "Этот мастер превратит ваш сервер в невидимый транзитный шлюз."
echo -e "Ваш провайдер будет видеть только ${C_GREEN}внутренний российский трафик${C_NC}.\n"

echo -e "${C_YELLOW}⚠️ ВАЖНОЕ УСЛОВИЕ:${C_NC}"
echo -e "Скрипт должен запускаться на сервере с ${C_GREEN}РОССИЙСКИМ IP${C_NC} (Яндекс и т.д.).\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Ошибка: Нужны права root (sudo bash ...)${C_NC}"
    exit 1
fi

# --- ШАГ 1 ---
echo -e "${C_WHITE}📌 ШАГ 1: ВЫБОР ИСТОЧНИКА ДАННЫХ${C_NC}"
echo -e "  1) Полная ссылка (vless:// / hy2://)\n  2) Адрес и порт (домен:порт)\n  3) Ввести вручную"
CHOICE=$(ask_step "👉 Выберите вариант [1-3]: " 3)

HAS_LINK=false
case $CHOICE in
    1)
        while true; do
            echo -e "${C_PURPLE}Вставьте вашу ссылку:${C_NC}"
            read -p "Ввод: " L
            if [[ "$L" == vless://* ]] || [[ "$L" == hy2://* ]] || [[ "$L" == hysteria2://* ]]; then
                HAS_LINK=true
                PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
                ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
                EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
                PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
                [[ "$L" == *"?"* ]] && PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1) || PARAMS=""
                [[ "$L" == *"#"* ]] && NAME=$(echo $L | sed -E 's/.*#(.*)/\1/') || NAME="Relay"
                break
            else
                echo -e "${C_RED}❌ Неверный формат ссылки! Попробуйте еще раз.${C_NC}"
            fi
        done
        ;;
    2)
        read -p "Введите адрес и порт (домен:8443): " L
        EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}')
        ;;
    3)
        read -p "🌍 IP или домен: " EU_HOST; read -p "🚪 ПОРТ: " PORT
        ;;
esac

# DNS Check
echo -e "\n🔍 Анализируем целевой адрес..."
if [[ $EU_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EU_IP=$EU_HOST
else
    EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)
    if [ -z "$EU_IP" ]; then echo -e "${C_RED}❌ Ошибка DNS!${C_NC}"; exit 1; fi
fi
echo -e "🎯 Цель: ${C_YELLOW}$EU_IP:$PORT${C_NC}"

# --- ШАГ 2 ---
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС${C_NC}"
echo -e "  1) Использовать ДОМЕН\n  2) Использовать просто IP"
CHOICE2=$(ask_step "👉 Ваш выбор [1-2]: " 2)

LOCAL_IP=$(curl -s ifconfig.me)
if [ "$CHOICE2" == "1" ]; then
    read -p "Введите домен: " DOMAIN; ENTRY="$DOMAIN"
else
    ENTRY="$LOCAL_IP"
fi

# --- ШАГ 3 ---
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ УСТАНОВКИ${C_NC}"
echo -e "  1) ОЧИСТИТЬ всё и начать с нуля\n  2) ДОБАВИТЬ новый порт к старым"
CHOICE3=$(ask_step "👉 Ваш выбор [1-2]: " 2)

# --- ШАГ 4: УСТАНОВКА ---
echo -e "\n${C_WHITE}📌 ШАГ 4: НАСТРОЙКА${C_NC}"
(
    echo 1 > /proc/sys/net/ipv4/ip_forward
    [ "$CHOICE3" == "1" ] && iptables -t nat -F
    for proto in tcp udp; do
        iptables -t nat -D PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done
    apt-get update -qq && apt-get install -y -qq nginx iptables-persistent > /dev/null
    systemctl restart nginx
    netfilter-persistent save
) > /dev/null 2>&1 &
spinner

# --- ФИНАЛ ---
echo -e "\n${C_GREEN}🎉 УСПЕШНО НАСТРОЕНО!${C_NC}"
if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    echo -e "${C_WHITE}Ваша ссылка:${C_NC}"
    echo -e "${C_GREEN}${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}${C_NC}"
else
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC} | Порт: ${C_GREEN}${PORT}${C_NC}"
fi
