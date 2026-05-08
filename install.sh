#!/bin/bash

# --- Настройка стилей (Яркие и насыщенные цвета) ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m' # Розовый / Маджента
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'
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

# --- Функция защиты от ошибок ввода ---
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
                echo -e "\n${C_YELLOW}⚠️ Слишком много попыток.${C_NC}"
                read -p "Продолжить (1) или выйти (2)? " retry
                [ "$retry" == "2" ] && exit 1
                attempts=0
            else
                echo -e "${C_RED}❌ Введите цифру от 1 до $2 (Попытка $attempts из $max_attempts)${C_NC}"
            fi
        fi
    done
}

clear
printf "${C_CYAN}"
cat << 'EOF'
    ____  _____ _        _ __   __
   |  _ \| ____| |      / \ \ / /
   | |_) |  _| | |     / _ \ \ / 
   |  _ <| |___| |___ / ___ \| |  
   |_| \_\_____|_____/_/   \_\_|  
EOF
printf "${C_NC}"
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v5.5 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

echo -e "${C_WHITE}💡 СУТЬ РАБОТЫ:${C_NC}"
echo -e "Этот скрипт маскирует ваш трафик под ${C_GREEN}российский${C_NC}."
echo -e "Провайдер увидит обращение к этому серверу (РФ), а не в Европу."

echo -e "\n${C_YELLOW}⚠️ ПРОВЕРКА IP:${C_NC}"
echo -e "Для обхода ограничений биллинга этот сервер ${C_RED}ДОЛЖЕН${C_NC} иметь российский IP."

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Нужны права root (sudo bash ...)${C_NC}"
    exit 1
fi

# --- ШАГ 1: ДАННЫЕ ---
echo -e "\n${C_WHITE}📌 ШАГ 1: ИСТОЧНИК ДАННЫХ${C_NC}"
echo -e "  1) Полная ссылка (vless:// / hy2://)\n  2) Адрес и порт (домен:порт)\n  3) Ввести вручную"
CHOICE=$(ask_step "👉 Ваш выбор [1-3]: " 3)

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
                echo -e "${C_RED}❌ Неверный формат!${C_NC}"
            fi
        done
        ;;
    2)
        read -p "Введите домен:порт : " L
        EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}')
        ;;
    3)
        read -p "🌍 Целевой IP/Домен: " EU_HOST; read -p "🚪 ПОРТ: " PORT
        ;;
esac

# DNS Check
echo -ne "\n🔍 Анализ цели... "
EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)
if [ -z "$EU_IP" ]; then echo -e "${C_RED}Ошибка DNS!${C_NC}"; exit 1; fi
echo -e "${C_GREEN}$EU_IP:$PORT${C_NC}"

# --- ШАГ 2: ВХОДНОЙ АДРЕС ---
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС${C_NC}"
echo -e "${C_CYAN}❓ ЧТО ЭТО:${C_NC} Это адрес, который вы укажете в приложении VPN."
echo -e "Это 'лицо' вашего сервера для провайдера. Лучше использовать домен."
echo -e "  1) У меня есть ДОМЕН\n  2) Использовать только IP"
CHOICE2=$(ask_step "👉 Ваш выбор [1-2]: " 2)

LOCAL_IP=$(curl -s ifconfig.me)
if [ "$CHOICE2" == "1" ]; then
    read -p "Введите домен (например, elite.dmtr.ru): " DOMAIN; ENTRY="$DOMAIN"
else
    ENTRY="$LOCAL_IP"
    echo -e "\n${C_YELLOW}💡 СПРАВКА: КАК СДЕЛАТЬ БЕСПЛАТНЫЙ ДОМЕН?${C_NC}"
    echo -e "  1. Зайдите на ${C_CYAN}freedns.afraid.org${C_NC}"
    echo -e "  2. Меню 'Dynamic DNS' -> 'Add'"
    echo -e "  3. Выберите домен, укажите поддомен и этот IP: ${C_GREEN}$LOCAL_IP${C_NC}"
    echo -e "  4. После этого запустите скрипт снова и выберите пункт 1."
fi

# --- ШАГ 3: РЕЖИМ ---
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ УСТАНОВКИ${C_NC}"
echo -e "  1) ОЧИСТИТЬ (для первого запуска)\n  2) ДОБАВИТЬ (для второго протокола)"
CHOICE3=$(ask_step "👉 Ваш выбор [1-2]: " 2)

# --- ШАГ 4: УСТАНОВКА ---
echo -e "\n${C_WHITE}📌 ШАГ 4: НАСТРОЙКА СИСТЕМЫ${C_NC}"
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
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 ВСЁ УСПЕШНО НАСТРОЕНО!${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

if [ "$HAS_LINK" = true ]; then
    # %2D = -, %5B = [, %5D = ]
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    echo -e "${C_WHITE}ВАША НОВАЯ ССЫЛКА (Скопируйте целиком):${C_NC}"
    echo -e "${C_PURPLE}${C_BOLD}${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}${C_NC}\n"
else
    echo -e "${C_WHITE}ДАННЫЕ ДЛЯ ВВОДА ВРУЧНУЮ:${C_NC}"
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC}"
    echo -e "Порт:  ${C_GREEN}${PORT}${C_NC}\n"
fi
echo -e "Добавьте эту ссылку в V2rayNG, NekoBox или Shadowrocket. Приятного пользования! 🚀"
