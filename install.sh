#!/bin/bash

# --- Настройка стилей и цветов ---
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_PURPLE='\033[1;35m'
C_RED='\033[0;31m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m' # Без цвета
C_BOLD='\033[1m'

# --- Функция красивого спиннера загрузки ---
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " ${C_PURPLE}[%c]${C_NC}  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf " \b\b\b\b"
}

# --- Очистка экрана и Логотип ---
clear
echo -e "${C_CYAN}${C_BOLD}"
echo "    ____  _____ _        _ __   __"
echo "   |  _ \| ____| |      / \\ \ / /"
echo "   | |_) |  _| | |     / _ \\ V / "
echo "   |  _ <| |___| |___ / ___ \| |  "
echo "   |_| \_\_____|_____/_/   \_\_|  "
echo "                                  "
echo -e "${C_PURPLE}  ✦ Super Relay Auto-Installer v3.0 ✦${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

# Проверка на права root
if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}❌ Ошибка: Хакинг отменяется. Нужны права root (sudo bash script.sh)${C_NC}"
  exit 1
fi

# Сбор данных
echo -e "${C_BOLD}Настройка маршрута:${C_NC}"
read -p "$(echo -e " 🌍 Введите IP ${C_CYAN}ЕВРОПЕЙСКОГО${C_NC} сервера: ")" EU_IP
read -p "$(echo -e " 🚪 Введите ${C_CYAN}ПОРТ${C_NC} для VPN (например, 8443): ")" PORT
echo ""

# --- Шаг 1: Маршрутизация ---
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

# --- Шаг 2: Установка Nginx ---
echo -ne "${C_BOLD}➜ Устанавливаем Web-сервер для маскировки (Nginx)...${C_NC}"
(
    apt-get update -qq > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
) & spinner
echo -e "${C_GREEN} ✔ Готово${C_NC}"

# --- Шаг 3: Генерация сайта ---
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

# --- Финал ---
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 ВСЁ УСПЕШНО НАСТРОЕНО!${C_NC}"
echo -e "    Трафик порта ${C_YELLOW}${PORT}${C_NC} летит на ${C_YELLOW}${EU_IP}:${PORT}${C_NC}"
echo -e "    Маскировка: зайди в браузер на свой домен (порт 80)."
echo -e "${C_RED}${C_BOLD} ⚠️  НЕ ЗАБУДЬ: В Яндекс Клауде должны быть открыты порты 80 и ${PORT}!${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"
