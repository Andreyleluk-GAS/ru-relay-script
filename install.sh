#!/bin/bash

# --- Настройка стилей ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m' 
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'
C_NC='\033[0m'

# Файл для хранения истории
HISTORY_FILE="/etc/relay_history.txt"

# --- Функция анимации ---
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
                echo -e "${C_RED}❌ Введите цифру от 1 до $2${C_NC}"
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
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v5.6 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Нужны права root (sudo bash ...)${C_NC}"
    exit 1
fi

# --- ГЛАВНОЕ МЕНЮ ---
echo -e "${C_WHITE}📱 ГЛАВНОЕ МЕНЮ:${C_NC}"
echo -e "  1) Настроить новое подключение (VLESS / Hysteria2)"
echo -e "  2) 📋 Посмотреть все ранее сделанные настройки"
echo -e "  3) 🗑️ Очистить историю настроек"
echo -e "  4) Выход\n"

MAIN_CHOICE=$(ask_step "👉 Ваш выбор [1-4]: " 4)

case $MAIN_CHOICE in
    2)
        echo -e "\n${C_WHITE}📋 ИСТОРИЯ ВАШИХ НАСТРОЕК:${C_NC}"
        if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
            echo -e "${C_PURPLE}${C_BOLD}"
            cat "$HISTORY_FILE"
            echo -e "${C_NC}"
        else
            echo -e "${C_YELLOW}История пока пуста. Настройте что-нибудь!${C_NC}"
        fi
        exit 0
        ;;
    3)
        rm -f "$HISTORY_FILE"
        echo -e "${C_GREEN}✔ История успешно очищена!${C_NC}"
        exit 0
        ;;
    4)
        exit 0
        ;;
esac

# --- ДАЛЕЕ ИДЕТ ЛОГИКА УСТАНОВКИ (ВАРИАНТ 1) ---

echo -e "\n${C_WHITE}💡 СУТЬ РАБОТЫ:${C_NC}"
echo -e "Скрипт маскирует трафик под российский. Провайдер увидит этот сервер (РФ)."

echo -e "\n${C_YELLOW}⚠️ ПРОВЕРКА IP:${C_NC}"
echo -e "Для обхода ограничений этот сервер ${C_RED}ДОЛЖЕН${C_NC} иметь российский IP.\n"

# --- ШАГ 1: ДАННЫЕ ---
echo -e "${C_WHITE}📌 ШАГ 1: ИСТОЧНИК ДАННЫХ${C_NC}"
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

echo -ne "\n🔍 Анализ цели... "
EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)
if [ -z "$EU_IP" ]; then echo -e "${C_RED}Ошибка DNS!${C_NC}"; exit 1; fi
echo -e "${C_GREEN}$EU_IP:$PORT${C_NC}"

# --- ШАГ 2: ВХОДНОЙ АДРЕС ---
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС${C_NC}"
echo -e "  1) У меня есть ДОМЕН\n  2) Использовать только IP"
CHOICE2=$(ask_step "👉 Ваш выбор [1-2]: " 2)

LOCAL_IP=$(curl -s ifconfig.me)
if [ "$CHOICE2" == "1" ]; then
    read -p "Введите домен: " DOMAIN; ENTRY="$DOMAIN"
else
    ENTRY="$LOCAL_IP"
    echo -e "\n${C_YELLOW}💡 СПРАВКА ПО FREEDNS:${C_NC}"
    echo -e "Привяжите этот IP: ${C_GREEN}$LOCAL_IP${C_NC} на ${C_CYAN}freedns.afraid.org${C_NC}"
fi

# --- ШАГ 3: РЕЖИМ ---
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ УСТАНОВКИ${C_NC}"
echo -e "  1) ОЧИСТИТЬ (первый запуск)\n  2) ДОБАВИТЬ (второй протокол)"
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
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    FINAL_LINK="${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_WHITE}ВАША НОВАЯ ССЫЛКА:${C_NC}"
    echo -e "${C_PURPLE}${C_BOLD}${FINAL_LINK}${C_NC}\n"
    # Сохраняем в историю
    echo "[$(date +'%Y-%m-%d %H:%M')] $FINAL_LINK" >> "$HISTORY_FILE"
else
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC} | Порт: ${C_GREEN}${PORT}${C_NC}\n"
    echo "[$(date +'%Y-%m-%d %H:%M')] Address: ${ENTRY} | Port: ${PORT}" >> "$HISTORY_FILE"
fi

echo -e "История сохранена в ${C_CYAN}$HISTORY_FILE${C_NC}"
echo -e "Для просмотра всех ссылок запустите скрипт и выберите пункт 2. 🚀"
