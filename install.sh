#!/bin/bash

# ==============================================================================
#  Universal Relay & Masking Wizard
#  Author: LeLUK
#  Version: 6.2 (Safe Reset Edition)
# ==============================================================================

# --- Настройка стилей ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m' 
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'
C_NC='\033[0m'

HISTORY_FILE="/etc/relay_history.txt"

# --- Улучшенный спиннер для конкретных задач ---
run_with_status() {
    local task_msg=$1
    shift
    echo -ne "  ${C_WHITE}${task_msg}...${C_NC}"
    
    # Запуск задачи в фоне
    "$@" > /dev/null 2>&1 &
    local pid=$!
    
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    while kill -0 $pid 2>/dev/null; do
        for frame in "${frames[@]}"; do
            printf "\r  ${C_CYAN}%s${C_NC} ${task_msg}..." "$frame"
            sleep 0.1
        done
    done
    wait $pid
    printf "\r  ${C_GREEN}✔${C_NC} ${task_msg} - Готово!\n"
}

ask_step() {
    local attempts=0
    while true; do
        read -p "$(echo -e "$1")" choice
        if [[ "$choice" =~ ^[1-$2]$ ]]; then
            echo "$choice"
            return 0
        else
            ((attempts++))
            if [ $attempts -ge 5 ]; then exit 1; fi
            echo -e "${C_RED}❌ Ошибка: Введите цифру от 1 до $2${C_NC}"
        fi
    done
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Ошибка: Нужен root${C_NC}"
    exit 1
fi

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
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v6.2 (Safe Reset) ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

echo -e "${C_WHITE}📱 ГЛАВНОЕ МЕНЮ:${C_NC}"
echo -e "  1) 🚀 Настроить новое подключение"
echo -e "  2) 📋 Посмотреть историю"
echo -e "  3) 🗑️  Очистить историю"
echo -e "  4) 🧨 ПОЛНЫЙ СБРОС СИСТЕМЫ И РЕБУТ"
echo -e "  5) 🚪 Выход\n"

MAIN_CHOICE=$(ask_step "👉 Ваш выбор [1-5]: " 5)

case $MAIN_CHOICE in
    2) [ -f "$HISTORY_FILE" ] && (echo -e "\n${C_PURPLE}${C_BOLD}"; cat "$HISTORY_FILE"; echo -e "${C_NC}") || echo -e "${C_YELLOW}История пуста.${C_NC}"; exit 0 ;;
    3) rm -f "$HISTORY_FILE"; echo -e "${C_GREEN}История очищена.${C_NC}"; exit 0 ;;
    4) 
        echo -e "\n${C_RED}${C_BOLD}🧨 ВНИМАНИЕ: ПОЛНОЕ УДАЛЕНИЕ МОСТА И СБРОС СЕРВЕРА${C_NC}"
        read -p "$(echo -e "👉 Вы абсолютно уверены? [y/N]: ")" confirm
        if [[ "$confirm" == [yYнН] ]]; then
            # Блокируем Ctrl+C, чтобы пользователь не сломал процесс очистки
            trap '' SIGINT
            
            echo -e "\n${C_YELLOW}⚙️ Начинаю процесс деинсталляции...${C_NC}"
            echo -e "${C_RED}⚠️ ПОЖАЛУЙСТА, НЕ ПРЕРЫВАЙТЕ ПРОЦЕСС${C_NC}\n"

            # 1. Отключаем форвардинг в ядре
            run_with_status "Отключение IP Forwarding" bash -c "sysctl -w net.ipv4.ip_forward=0 && rm -f /etc/sysctl.d/99-relay.conf"

            # 2. Чистим Iptables
            run_with_status "Очистка правил NAT и Iptables" bash -c "iptables -t nat -F && iptables -t nat -X && iptables -F && netfilter-persistent save"

            # 3. Удаляем Nginx (Ждем завершения работы APT)
            export DEBIAN_FRONTEND=noninteractive
            run_with_status "Полное удаление Nginx и файлов заглушки" bash -c "apt-get purge -y nginx nginx-common nginx-full >/dev/null && apt-get autoremove -y >/dev/null && rm -rf /var/www/html"

            # 4. Удаляем историю
            run_with_status "Очистка журналов и истории" rm -f "$HISTORY_FILE"

            echo -e "\n${C_GREEN}${C_BOLD}🎉 СЕРВЕР ПОЛНОСТЬЮ ОЧИЩЕН!${C_NC}"
            echo -e "------------------------------------------------"
            echo -e "Система уходит в перезагрузку через 5 секунд..."
            echo -e "После этого сервер будет как новый."
            echo -e "------------------------------------------------"
            
            sleep 5
            # Принудительный ребут, игнорируя блокировщики
            systemctl reboot -i
            exit 0
        else
            echo "Сброс отменен."
            exit 0
        fi
        ;;
    5) exit 0 ;;
esac

# --- ШАГ 1: ИСТОЧНИК ДАННЫХ ---
echo -e "\n${C_WHITE}📌 ШАГ 1: ДАННЫЕ ЗАРУБЕЖНОГО СЕРВЕРА${C_NC}"
read -p "Выберите 1 (Ссылка), 2 (Домен:порт) или 3 (Вручную): " CHOICE_IN

HAS_LINK=false
case $CHOICE_IN in
    1)
        while true; do
            read -p "Вставьте ссылку: " L
            if [[ "$L" == vless://* ]] || [[ "$L" == hy2://* ]] || [[ "$L" == hysteria2://* ]] || [[ "$L" == tg://* ]]; then
                HAS_LINK=true
                PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
                if [[ "$PROTO" == "tg" ]]; then
                    EU_HOST=$(echo $L | sed -E 's/.*server=([^&]+).*/\1/'); PORT=$(echo $L | sed -E 's/.*port=([^&]+).*/\1/')
                    PARAMS=$(echo $L | sed -E 's/.*(secret=[^&]+).*/\1/'); ID=""; NAME="TG_Proxy"
                else
                    ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
                    EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
                    PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
                    [[ "$L" == *"?"* ]] && PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1) || PARAMS=""
                    [[ "$L" == *"#"* ]] && NAME=$(echo $L | sed -E 's/.*#(.*)/\1/') || NAME="Relay"
                fi
                break
            else
                echo -e "${C_RED}❌ Ошибка ссылки!${C_NC}"
            fi
        done
        ;;
    2) read -p "Домен:порт : " L; EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}') ;;
    3) read -p "IP: " EU_HOST; read -p "Порт: " PORT ;;
esac

EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)

# --- ШАГ 2: ВХОДНОЙ АДРЕС ---
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС${C_NC}"
read -p "Ваш домен (или Enter): " DOMAIN
LOCAL_IP=$(curl -s ifconfig.me)
[ -z "$DOMAIN" ] && ENTRY="$LOCAL_IP" || ENTRY="$DOMAIN"

# --- ШАГ 3: РЕЖИМ ---
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ МАРШРУТИЗАЦИИ${C_NC}"
CHOICE3=$(ask_step "  1) ОЧИСТИТЬ старое\n  2) ДОБАВИТЬ новый\n👉 Ваш выбор: " 2)

# --- ШАГ 4: УСТАНОВКА ---
echo -e "\n${C_WHITE}📌 ШАГ 4: НАСТРОЙКА СИСТЕМЫ${C_NC}"
(
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-relay.conf
    sysctl -p /etc/sysctl.d/99-relay.conf > /dev/null 2>&1
    [ "$CHOICE3" == "1" ] && iptables -t nat -F
    for proto in tcp udp; do
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done
    export DEBIAN_FRONTEND=noninteractive
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update -qq && apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
    mkdir -p /var/www/html
    echo "<h1>Node $ENTRY Status: Online</h1>" > /var/www/html/index.html
    systemctl restart nginx && netfilter-persistent save
) > /dev/null 2>&1 &
run_with_status "Применяю настройки моста" sleep 1

# --- ФИНАЛ ---
echo -e "\n${C_GREEN}${C_BOLD} 🎉 СИСТЕМА ГОТОВА!${C_NC}\n"
if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    [ "$PROTO" == "tg" ] && FINAL_LINK="tg://proxy?server=${ENTRY}&port=${PORT}&${PARAMS}" || FINAL_LINK="${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_PURPLE}${C_BOLD}${FINAL_LINK}${C_NC}\n"
    echo "[$(date +'%F %R')] $FINAL_LINK" >> "$HISTORY_FILE"
fi
