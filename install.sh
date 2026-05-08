#!/bin/bash

# ==============================================================================
#  Universal Relay & Masking Wizard
#  Author: LeLUK
#  Description: Превращает сервер в прозрачный шлюз (Relay) для обхода 
#  ограничений биллинга зарубежного трафика, маскируя его под внутренний (РФ).
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
    printf "\r  ${C_GREEN}✔ Успешно завершено!                           ${C_NC}\n"
}

# --- Функция защиты от ошибок ввода ---
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
                read -p "Слишком много ошибок. Продолжить (1) или выйти (2)? " retry
                [ "$retry" == "2" ] && exit 1
                attempts=0
            else
                echo -e "${C_RED}❌ Ошибка: Введите цифру от 1 до $2${C_NC}"
            fi
        fi
    done
}

# --- Проверка прав ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Ошибка: Скрипт необходимо запустить с правами root (sudo bash ...)${C_NC}"
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
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v6.1 (Full Lifecycle) ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

# --- ГЛАВНОЕ МЕНЮ ---
echo -e "${C_WHITE}📱 ГЛАВНОЕ МЕНЮ:${C_NC}"
echo -e "  1) 🚀 Настроить новое подключение (VPN / Proxy)"
echo -e "  2) 📋 Посмотреть историю настроек"
echo -e "  3) 🗑️ Очистить историю"
echo -e "  4) 🧨 ПОЛНЫЙ СБРОС (Удалить мост, Nginx и перезагрузить)"
echo -e "  5) 🚪 Выход\n"

MAIN_CHOICE=$(ask_step "👉 Ваш выбор [1-5]: " 5)

case $MAIN_CHOICE in
    2) [ -f "$HISTORY_FILE" ] && (echo -e "\n${C_PURPLE}${C_BOLD}"; cat "$HISTORY_FILE"; echo -e "${C_NC}") || echo -e "${C_YELLOW}История пуста.${C_NC}"; exit 0 ;;
    3) rm -f "$HISTORY_FILE"; echo -e "${C_GREEN}История успешно очищена.${C_NC}"; exit 0 ;;
    4) 
        echo -e "\n${C_RED}🧨 ВНИМАНИЕ: Это действие полностью удалит настройки маршрутизации,${C_NC}"
        echo -e "${C_RED}веб-сервер Nginx, очистит историю и ПЕРЕЗАГРУЗИТ сервер.${C_NC}"
        read -p "$(echo -e "👉 Вы абсолютно уверены? [y/N]: ")" confirm
        # Понимаем "y", "Y", а также русские "н" и "Н", если забыли сменить раскладку
        if [[ "$confirm" == "y" || "$confirm" == "Y" || "$confirm" == "н" || "$confirm" == "Н" ]]; then
            echo -e "\n${C_WHITE}📌 ПОЛНАЯ ОЧИСТКА СИСТЕМЫ${C_NC}"
            (
                # 1. Отключаем форвардинг
                sysctl -w net.ipv4.ip_forward=0 > /dev/null 2>&1
                rm -f /etc/sysctl.d/99-relay.conf
                
                # 2. Очищаем Iptables
                iptables -t nat -F
                iptables -t nat -X
                iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
                if command -v ufw > /dev/null; then ufw delete allow 80/tcp > /dev/null 2>&1; fi
                netfilter-persistent save > /dev/null 2>&1
                
                # 3. Удаляем Nginx и заглушку
                export DEBIAN_FRONTEND=noninteractive
                systemctl stop nginx > /dev/null 2>&1
                apt-get purge -y -qq nginx nginx-common > /dev/null 2>&1
                apt-get autoremove -y -qq > /dev/null 2>&1
                rm -rf /var/www/html
                
                # 4. Удаляем историю
                rm -f "$HISTORY_FILE"
            ) > /dev/null 2>&1 &
            spinner
            echo -e "\n${C_GREEN}${C_BOLD}🎉 Сервер успешно возвращен к заводским настройкам!${C_NC}"
            echo -e "Система уходит в перезагрузку. SSH-сессия будет разорвана."
            echo -e "Подключитесь заново через минуту. 👋\n"
            sleep 3
            reboot
            exit 0
        else
            echo -e "${C_YELLOW}Удаление отменено. Сервер работает в прежнем режиме.${C_NC}"
            exit 0
        fi
        ;;
    5) echo "До свидания!"; exit 0 ;;
esac

# --- ШАГ 1: ИСТОЧНИК ДАННЫХ ---
echo -e "\n${C_WHITE}📌 ШАГ 1: ДАННЫЕ ЗАРУБЕЖНОГО СЕРВЕРА${C_NC}"
echo -e "  1) Вставить полную ссылку (vless:// / hy2:// / tg://)"
echo -e "  2) Ввести Адрес и Порт (например, server.com:8443)"
echo -e "  3) Ввести IP и Порт вручную по отдельности"
CHOICE=$(ask_step "👉 Ваш выбор [1-3]: " 3)

HAS_LINK=false
case $CHOICE in
    1)
        while true; do
            read -p "Вставьте ссылку: " L
            if [[ "$L" == vless://* ]] || [[ "$L" == hy2://* ]] || [[ "$L" == hysteria2://* ]] || [[ "$L" == tg://* ]]; then
                HAS_LINK=true
                PROTO=$(echo $L | sed -E 's/^([a-zA-Z2]+):\/\/.*/\1/')
                
                # Парсинг отличается для tg:// и обычных VPN
                if [[ "$PROTO" == "tg" ]]; then
                    EU_HOST=$(echo $L | sed -E 's/.*server=([^&]+).*/\1/')
                    PORT=$(echo $L | sed -E 's/.*port=([^&]+).*/\1/')
                    PARAMS=$(echo $L | sed -E 's/.*(secret=[^&]+).*/\1/')
                    ID=""
                    NAME="Telegram_Proxy"
                else
                    ID=$(echo $L | sed -E 's/^[a-zA-Z2]+:\/\/([^@]+)@.*/\1/')
                    EU_HOST=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
                    PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
                    [[ "$L" == *"?"* ]] && PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' | cut -d'#' -f1) || PARAMS=""
                    [[ "$L" == *"#"* ]] && NAME=$(echo $L | sed -E 's/.*#(.*)/\1/') || NAME="Relay"
                fi
                break
            else
                echo -e "${C_RED}❌ Неверный формат ссылки! Попробуйте еще раз.${C_NC}"
            fi
        done
        ;;
    2) read -p "Введите домен и порт (через двоеточие): " L; EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}') ;;
    3) read -p "🌍 Целевой IP или Домен: " EU_HOST; read -p "🚪 ПОРТ: " PORT ;;
esac

EU_IP=$(getent ahosts "$EU_HOST" | awk '{ print $1 }' | head -n 1)

# --- ШАГ 2: ВХОДНОЙ АДРЕС ---
echo -e "\n${C_WHITE}📌 ШАГ 2: ВХОДНОЙ АДРЕС (Для маскировки)${C_NC}"
echo -e "Укажите домен, который привязан к этому российскому серверу."
echo -e "Если домена нет, просто нажмите Enter (будет использован IP)."
read -p "Ваш домен: " DOMAIN
LOCAL_IP=$(curl -s ifconfig.me)
[ -z "$DOMAIN" ] && ENTRY="$LOCAL_IP" || ENTRY="$DOMAIN"

# --- ШАГ 3: РЕЖИМ УСТАНОВКИ ---
echo -e "\n${C_WHITE}📌 ШАГ 3: РЕЖИМ МАРШРУТИЗАЦИИ${C_NC}"
echo -e "  1) 🧹 ОЧИСТИТЬ старые правила (Если настраиваете первый раз)"
echo -e "  2) ➕ ДОБАВИТЬ новый порт (Если добавляете второй протокол)"
CHOICE3=$(ask_step "👉 Ваш выбор [1-2]: " 2)

# --- ШАГ 4: УСТАНОВКА И НАСТРОЙКА ---
echo -e "\n${C_WHITE}📌 ШАГ 4: АВТОМАТИЧЕСКАЯ НАСТРОЙКА СИСТЕМЫ${C_NC}"

iptables -I INPUT -p tcp --dport 80 -j ACCEPT > /dev/null 2>&1
if command -v ufw > /dev/null; then ufw allow 80/tcp > /dev/null 2>&1; fi

(
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-relay.conf
    sysctl -p /etc/sysctl.d/99-relay.conf > /dev/null 2>&1

    [ "$CHOICE3" == "1" ] && iptables -t nat -F

    for proto in tcp udp; do
        iptables -t nat -D PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done

    export DEBIAN_FRONTEND=noninteractive
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    
    apt-get update -qq && apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
    
    mkdir -p /var/www/html
    cat <<EOF > /var/www/html/index.html
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Maintenance</title><style>body{background:#0f0f11;color:#e0e0e0;text-align:center;padding:15vh 10%;font-family:sans-serif;}</style></head>
<body><h1>🛠 Node Status: Maintenance</h1><p>Scheduled backend upgrades in progress. HTTP traffic is suspended.</p><p><i>Node: $ENTRY</i></p></body></html>
EOF
    systemctl enable nginx > /dev/null 2>&1
    systemctl restart nginx > /dev/null 2>&1
    netfilter-persistent save > /dev/null 2>&1
) > /dev/null 2>&1 &
spinner

# --- ФИНАЛ ---
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 СИСТЕМА УСПЕШНО НАСТРОЕНА!${C_NC}"
echo -e "${C_CYAN}================================================\n"

if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    
    # Собираем ссылку в зависимости от протокола
    if [[ "$PROTO" == "tg" ]]; then
        FINAL_LINK="tg://proxy?server=${ENTRY}&port=${PORT}&${PARAMS}"
    else
        FINAL_LINK="${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}"
    fi
    
    echo -e "${C_WHITE}🔗 ВАША НОВАЯ ССЫЛКА (Скопируйте целиком):${C_NC}"
    echo -e "${C_PURPLE}${C_BOLD}${FINAL_LINK}${C_NC}\n"
    echo "[$(date +'%Y-%m-%d %H:%M')] $FINAL_LINK" >> "$HISTORY_FILE"
else
    echo -e "${C_WHITE}Ваши данные для подключения:${C_NC}"
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC} | Порт: ${C_GREEN}${PORT}${C_NC}\n"
    echo "[$(date +'%Y-%m-%d %H:%M')] Address: ${ENTRY} | Port: ${PORT}" >> "$HISTORY_FILE"
fi

echo -e "Заглушка (веб-сайт) доступна по адресу: ${C_CYAN}http://$ENTRY${C_NC}"
