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
echo -e "${C_PURPLE}${C_BOLD}  ✦ Super Relay Wizard v6.0 (GitHub Edition) ✦${C_NC}"
echo -e "${C_YELLOW}             by LeLUK${C_NC}\n"

# --- ГЛАВНОЕ МЕНЮ ---
echo -e "${C_WHITE}📱 ГЛАВНОЕ МЕНЮ:${C_NC}"
echo -e "  1) Настроить новое подключение (VLESS / Hysteria2 и др.)"
echo -e "  2) 📋 Посмотреть историю настроек"
echo -e "  3) 🗑️ Очистить историю"
echo -e "  4) Выход\n"

MAIN_CHOICE=$(ask_step "👉 Ваш выбор [1-4]: " 4)

case $MAIN_CHOICE in
    2) [ -f "$HISTORY_FILE" ] && (echo -e "\n${C_PURPLE}${C_BOLD}"; cat "$HISTORY_FILE"; echo -e "${C_NC}") || echo -e "${C_YELLOW}История пуста.${C_NC}"; exit 0 ;;
    3) rm -f "$HISTORY_FILE"; echo -e "${C_GREEN}История успешно очищена.${C_NC}"; exit 0 ;;
    4) echo "До свидания!"; exit 0 ;;
esac

# --- ШАГ 1: ИСТОЧНИК ДАННЫХ ---
echo -e "\n${C_WHITE}📌 ШАГ 1: ДАННЫЕ ЗАРУБЕЖНОГО СЕРВЕРА${C_NC}"
echo -e "  1) Вставить полную ссылку (vless:// / hy2://)"
echo -e "  2) Ввести Адрес и Порт (например, server.com:8443)"
echo -e "  3) Ввести IP и Порт вручную по отдельности"
CHOICE=$(ask_step "👉 Ваш выбор [1-3]: " 3)

HAS_LINK=false
case $CHOICE in
    1)
        while true; do
            read -p "Вставьте ссылку: " L
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
    2) read -p "Введите домен и порт (через двоеточие): " L; EU_HOST=$(echo "$L" | awk -F: '{print $1}'); PORT=$(echo "$L" | awk -F: '{print $2}') ;;
    3) read -p "🌍 Целевой IP или Домен: " EU_HOST; read -p "🚪 ПОРТ: " PORT ;;
esac

# Преобразование домена в IP, если необходимо
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

# Сразу открываем порт 80 для заглушки (чтобы не блокировал UFW)
iptables -I INPUT -p tcp --dport 80 -j ACCEPT > /dev/null 2>&1
if command -v ufw > /dev/null; then ufw allow 80/tcp > /dev/null 2>&1; fi

(
    # 1. Делаем переадресацию трафика постоянной (переживет перезагрузку)
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-relay.conf
    sysctl -p /etc/sysctl.d/99-relay.conf > /dev/null 2>&1

    # 2. Очистка правил, если выбрано
    [ "$CHOICE3" == "1" ] && iptables -t nat -F

    # 3. Настройка Iptables для проброса портов (TCP и UDP)
    for proto in tcp udp; do
        iptables -t nat -D PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done

    # 4. Установка пакетов без зависаний
    export DEBIAN_FRONTEND=noninteractive
    # Автоматически отвечаем "Да" на вопросы iptables-persistent
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    
    apt-get update -qq && apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
    
    # 5. Создание страницы-заглушки (Сайт-маскировка)
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
    # Кодируем спецсимволы: - это %2D, [ это %5B, ] это %5D
    NEW_NAME="${NAME}%2DTUN%5B${LOCAL_IP}%5D"
    FINAL_LINK="${PROTO}://${ID}@${ENTRY}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_WHITE}🔗 ВАША НОВАЯ ССЫЛКА (Скопируйте целиком):${C_NC}"
    echo -e "${C_PURPLE}${C_BOLD}${FINAL_LINK}${C_NC}\n"
    # Сохраняем в историю
    echo "[$(date +'%Y-%m-%d %H:%M')] $FINAL_LINK" >> "$HISTORY_FILE"
else
    echo -e "${C_WHITE}Ваши данные для подключения:${C_NC}"
    echo -e "Адрес: ${C_GREEN}${ENTRY}${C_NC} | Порт: ${C_GREEN}${PORT}${C_NC}\n"
    echo "[$(date +'%Y-%m-%d %H:%M')] Address: ${ENTRY} | Port: ${PORT}" >> "$HISTORY_FILE"
fi

echo -e "Заглушка (веб-сайт) доступна по адресу: ${C_CYAN}http://$ENTRY${C_NC}"
