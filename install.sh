#!/bin/bash

# --- Настройка стилей ---
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_PURPLE='\033[1;35m'
C_RED='\033[0;31m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m'
C_BOLD='\033[1m'

spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid 2>/dev/null)" ]; do
        local temp=${spinstr#?}
        printf " ${C_PURPLE}[%c]${C_NC}  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf " \b\b\b\b"
}

clear
echo -e "${C_CYAN}${C_BOLD}"
echo "    ____  _____ _        _ __   __"
echo "   |  _ \| ____| |      / \\ \ / /"
echo "   | |_) |  _| | |     / _ \\ V / "
echo "   |  _ <| |___| |___ / ___ \| |  "
echo "   |_| \_\_____|_____/_/   \_\_|  "
echo "                                  "
echo -e "${C_PURPLE}  ✦ Super Relay Auto-Installer v4.0 ✦${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}❌ Ошибка: Нужны права root (sudo bash script.sh)${C_NC}"
  exit 1
fi

# --- БЛОК 1: Ввод данных (Ссылка или Руками) ---
echo -e "${C_BOLD}Как вы хотите настроить подключение?${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} У меня есть полная ссылка (vless://...)"
echo -e "  ${C_CYAN}2)${C_NC} Ввести IP и Порт вручную"
read -p "$(echo -e "Выберите вариант ${C_YELLOW}(1 или 2)${C_NC}: ")" INPUT_METHOD
echo ""

HAS_LINK=false

if [ "$INPUT_METHOD" == "1" ]; then
    read -p "🔗 Вставьте вашу VLESS ссылку: " VLESS_LINK
    
    if [[ "$VLESS_LINK" == vless://* ]]; then
        HAS_LINK=true
        DATA="${VLESS_LINK#vless://}"
        UUID="${DATA%%@*}"
        REST="${DATA#*@}"
        EU_IP="${REST%%:*}"
        REST="${REST#*:}"
        PORT="${REST%%?*}"
        REST="${REST#*?}"
        
        if [[ "$REST" == *#* ]]; then
            PARAMS="${REST%%#*}"
            NAME="${REST#*#}"
        else
            PARAMS="$REST"
            NAME="MyRelay"
        fi
        echo -e "${C_GREEN}✔ Ссылка распознана! IP: $EU_IP | Порт: $PORT${C_NC}\n"
    else
        echo -e "${C_RED}❌ Ошибка: Неверный формат ссылки. Она должна начинаться с vless://${C_NC}"
        exit 1
    fi
else
    read -p "🌍 Введите IP адрес зарубежного сервера: " EU_IP
    read -p "🚪 Введите ПОРТ: " PORT
    echo ""
fi

# --- БЛОК 2: Ввод Домена ---
echo -e "${C_BOLD}У вас есть домен, привязанный к этому российскому серверу?${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} Да, есть (например, elite.dmtr.ru)"
echo -e "  ${C_CYAN}2)${C_NC} Нет, использовать просто IP сервера"
read -p "$(echo -e "Выберите вариант ${C_YELLOW}(1 или 2)${C_NC}: ")" DOMAIN_CHOICE

if [ "$DOMAIN_CHOICE" == "1" ]; then
    read -p "🌐 Введите ваш домен: " ENTRY_ADDRESS
else
    echo -ne "🔍 Определяем IP этого сервера... "
    ENTRY_ADDRESS=$(curl -s ifconfig.me)
    if [ -z "$ENTRY_ADDRESS" ]; then
        ENTRY_ADDRESS=$(curl -s icanhazip.com) # Резервный способ
    fi
    echo -e "${C_GREEN}$ENTRY_ADDRESS${C_NC}"
fi
echo ""

# --- БЛОК 3: Настройка сервера (iptables + nginx) ---
echo -ne "${C_BOLD}➜ Настраиваем ядро и маршрутизацию (iptables)...${C_NC}"
(
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

    iptables -t nat -D PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
    iptables -t nat -D POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
    iptables -t nat -D POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null

    iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
    iptables -t nat -A POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE
    iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
    iptables -t nat -A POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE

    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $PORT -j ACCEPT
) & spinner
echo -e "${C_GREEN} ✔ Готово${C_NC}"

echo -ne "${C_BOLD}➜ Устанавливаем Web-сервер для маскировки (Nginx)...${C_NC}"
(
    apt-get update -qq > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
) & spinner
echo -e "${C_GREEN} ✔ Готово${C_NC}"

echo -ne "${C_BOLD}➜ Создаем страницу-заглушку и сохраняем правила...${C_NC}"
(
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Maintenance</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #0f0f11; color: #e0e0e0; text-align: center; padding: 50px; }
        .container { background: #1c1c1e; max-width: 600px; margin: 0 auto; padding: 40px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 1px solid #333; }
        h1 { color: #ffffff; font-weight: 300; letter-spacing: 1px; }
        p { color: #888; line-height: 1.8; font-size: 16px; }
        .icon { font-size: 50px; margin-bottom: 20px; animation: pulse 2s infinite; }
        @keyframes pulse { 0% { opacity: 0.7; } 50% { opacity: 1; text-shadow: 0 0 20px #00e5ff; } 100% { opacity: 0.7; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">⬡</div>
        <h1>Node Status: Maintenance</h1>
        <p>This server is currently undergoing scheduled backend upgrades. Secure protocols remain active. HTTP traffic is temporarily suspended.</p>
        <p><em>Sysadmin Department</em></p>
    </div>
</body>
</html>
EOF

    systemctl restart nginx > /dev/null 2>&1
    netfilter-persistent save > /dev/null 2>&1
) & spinner
echo -e "${C_GREEN} ✔ Готово${C_NC}"

# --- БЛОК 4: Вывод результата ---
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 СЕРВЕР УСПЕШНО НАСТРОЕН!${C_NC}"
echo -e "    Трафик порта ${C_YELLOW}${PORT}${C_NC} перенаправляется на ${C_YELLOW}${EU_IP}:${PORT}${C_NC}"
echo -e "    Маскировка: зайди в браузер на ${C_YELLOW}http://${ENTRY_ADDRESS}${C_NC}"
echo -e "${C_RED}    ⚠️  В Яндекс Клауде должны быть открыты порты 80 и ${PORT}!${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

# Если была ссылка, генерируем новую
if [ "$HAS_LINK" = true ]; then
    # %2D - это дефис (-) в URL-кодировке
    NEW_NAME="${NAME}%2DWhiteList"
    FINAL_LINK="vless://${UUID}@${ENTRY_ADDRESS}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_PURPLE}${C_BOLD}👇 ВАША НОВАЯ ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ 👇${C_NC}"
    echo -e "${C_GREEN}${FINAL_LINK}${C_NC}\n"
    echo -e "Просто скопируйте её и вставьте в V2rayNG, NekoBox или Shadowrocket!"
fi
