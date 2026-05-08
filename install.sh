#!/bin/bash

# --- Настройка стилей (как в 5.7) ---
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_PURPLE='\033[1;35m' 
C_YELLOW='\033[1;33m'
C_WHITE='\033[1;37m'
C_RED='\033[1;31m'
C_BOLD='\033[1m'
C_NC='\033[0m'

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

# --- Ожидание APT ---
wait_for_apt() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do
        sleep 2
    done
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
            if [ $attempts -ge 5 ]; then
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
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v5.9 ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Нужны права root!${C_NC}"
    exit 1
fi

# ГЛАВНОЕ МЕНЮ
echo -e "${C_WHITE}📱 ГЛАВНОЕ МЕНЮ:${C_NC}"
echo -e "  1) Настроить новое подключение\n  2) 📋 Посмотреть историю\n  3) 🗑️ Очистить историю\n  4) Выход\n"
MAIN_CHOICE=$(ask_step "👉 Ваш выбор [1-4]: " 4)

case $MAIN_CHOICE in
    2) [ -f "$HISTORY_FILE" ] && cat "$HISTORY_FILE" || echo "История пуста"; exit 0 ;;
    3) rm -f "$HISTORY_FILE"; echo "Очищено"; exit 0 ;;
    4) exit 0 ;;
esac

# ШАГ 1
echo -e "\n${C_WHITE}📌 ШАГ 1: ИСТОЧНИК ДАННЫХ${C_NC}"
echo -e "  1) Ссылка\n  2) Домен:порт\n  3) Вручную"
CHOICE=$(ask_step "👉 Ваш выбор [1-3]: " 3)

HAS_LINK=false
case $CHOICE in
    1)
        read -p "Вставьте ссылку: " L
        HAS_LINK=true
        PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
        ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
        EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
        PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
        [[ "$L" == *"?"* ]] && PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1) || PARAMS=""
        [[ "$L" == *"#"* ]] && NAME=$(echo $L | sed -E 's/.*#(.*)/\1/') || NAME="Relay"
        ;;
    2) read -p "Домен:порт : " L; EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}') ;;
    3) read -p "IP/Домен: " EU_HOST; read -p "ПОРТ: " PORT ;;
esac

EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)

# ШАГ 2
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС${C_NC}"
read -p "Введите ваш домен (или Enter для IP): " DOMAIN
LOCAL_IP=$(curl -s ifconfig.me)
[ -z "$DOMAIN" ] && ENTRY="$LOCAL_IP" || ENTRY="$DOMAIN"

# ШАГ 3
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ${C_NC}"
CHOICE3=$(ask_step "  1) Очистить старое\n  2) Добавить порт\n👉 Ваш выбор: " 2)

# ШАГ 4
echo -e "\n${C_WHITE}📌 ШАГ 4: НАСТРОЙКА СИСТЕМЫ${C_NC}"
wait_for_apt

echo -e "⚙️ Настраиваем маршруты и открываем Firewall..."
(
    echo 1 > /proc/sys/net/ipv4/ip_forward
    [ "$CHOICE3" == "1" ] && iptables -t nat -F

    # --- ДОБАВЛЕНО: ПРИНУДИТЕЛЬНОЕ ОТКРЫТИЕ ПОРТОВ ---
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $PORT -j ACCEPT
    if command -v ufw > /dev/null; then
        ufw allow 80/tcp > /dev/null
        ufw allow $PORT/tcp > /dev/null
        ufw allow $PORT/udp > /dev/null
    fi
    # -----------------------------------------------

    for proto in tcp udp; do
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done
) > /dev/null 2>&1 &
spinner

echo -e "🛡️ Установка заглушки Nginx..."
(
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq nginx iptables-persistent < /dev/null
    
    cat <<EOF > /var/www/html/index.html
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Maintenance</title><style>body{background:#0f0f11;color:#e0e0e0;text-align:center;padding:15vh 10%;font-family:sans-serif;}</style></head>
<body><h1>🛠 Node Status: Maintenance</h1><p>Scheduled backend upgrades in progress. Services are active.</p><p><i>$ENTRY</i></p></body></html>
EOF
    systemctl enable nginx > /dev/null
    systemctl restart nginx > /dev/null
    netfilter-persistent save > /dev/null
) > /dev/null 2>&1 &
spinner

# ФИНАЛ
echo -e "\n${C_GREEN}${C_BOLD} 🎉 ВСЁ УСПЕШНО НАСТРОЕНО!${C_NC}\n"
if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    FINAL_LINK="${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_PURPLE}${C_BOLD}${FINAL_LINK}${C_NC}\n"
    echo "[$(date +'%F %R')] $FINAL_LINK" >> "$HISTORY_FILE"
else
    echo -e "IP: $ENTRY | Port: $PORT"
fi
