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
echo -e "${C_PURPLE}  ✦ Super Relay Auto-Installer v4.2 (Full Info) ✦${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

# 1. Сразу определяем локальный IP сервера
echo -ne "🔎 Определение локального адреса... "
LOCAL_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
echo -e "${C_GREEN}$LOCAL_IP${C_NC}"
echo -e "${C_YELLOW}Вы настраиваете этот сервер в качестве входного шлюза (Relay).${C_NC}\n"

if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}❌ Ошибка: Нужны права root (sudo bash script.sh)${C_NC}"
  exit 1
fi

# Выбор метода ввода
echo -e "${C_BOLD}Шаг 1: Получение данных о зарубежном сервере${C_NC}"
echo -e "  ${C_CYAN}1)${C_NC} Вставить VLESS ссылку"
echo -e "  ${C_CYAN}2)${C_NC} Ввести данные вручную"
read -p "Выберите вариант: " INPUT_METHOD

HAS_LINK=false
if [ "$INPUT_METHOD" == "1" ]; then
    read -p "🔗 Вставьте ссылку: " VLESS_LINK
    if [[ "$VLESS_LINK" == vless://* ]]; then
        HAS_LINK=true
        UUID=$(echo $VLESS_LINK | sed -E 's/vless:\/\/([^@]+)@.*/\1/')
        EU_IP=$(echo $VLESS_LINK | sed -E 's/.*@([^:]+):.*/\1/')
        PORT=$(echo $VLESS_LINK | sed -E 's/.*:([0-9]+)\?.*/\1/')
        # Если порт не нашелся через ?, пробуем через #
        if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then PORT=$(echo $VLESS_LINK | sed -E 's/.*:([0-9]+)#.*/\1/'); fi
        PARAMS=$(echo $VLESS_LINK | sed -E 's/.*\?(.*)#.*/\1/')
        NAME=$(echo $VLESS_LINK | sed -E 's/.*#(.*)/\1/')
    fi
else
    read -p "🌍 IP зарубежного сервера: " EU_IP
    read -p "🚪 Порт VPN: " PORT
fi

# Подтверждение маршрута
echo -e "\n${C_BOLD}🚀 Маршрут трафика будет выглядеть так:${C_NC}"
echo -e "   [Ваш ПК] ———> ${C_GREEN}$LOCAL_IP${C_NC}:${C_YELLOW}$PORT${C_NC} (РФ) ———> ${C_CYAN}$EU_IP${C_NC}:${C_YELLOW}$PORT${C_NC} (Европа)"
echo ""

# Информация о трафике
echo -e "${C_PURPLE}📊 Справка по учету трафика:${C_NC}"
echo -e "   Трафик будет дублироваться. Если вы скачаете файл 1 ГБ:"
echo -e "   • На ${C_CYAN}европейском${C_NC} сервере потратится 1 ГБ (входящий) + 1 ГБ (исходящий)."
echo -e "   • На ${C_GREEN}этом (РФ)${C_NC} сервере потратится 1 ГБ (входящий) + 1 ГБ (исходящий)."
echo -e "   ${C_YELLOW}Итого:${C_NC} учитывайте лимиты на обоих серверах!\n"

read -p "Продолжить настройку? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then exit; fi

# Ввод домена
echo -e "\n${C_BOLD}Шаг 2: Входной адрес${C_NC}"
read -p "У вас есть привязанный домен? (Введите его или нажмите Enter для использования IP): " ENTRY_ADDRESS
if [ -z "$ENTRY_ADDRESS" ]; then ENTRY_ADDRESS=$LOCAL_IP; fi

# Настройка
echo -ne "\n${C_BOLD}➜ Настройка iptables...${C_NC}"
(
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    for proto in tcp udp; do
        iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
        iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
    done
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
) & spinner
echo -e "${C_GREEN} ✔${C_NC}"

echo -ne "${C_BOLD}➜ Установка маскировки (Nginx)...${C_NC}"
(
    apt-get update -qq > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx iptables-persistent > /dev/null 2>&1
    systemctl restart nginx > /dev/null 2>&1
    netfilter-persistent save > /dev/null 2>&1
) & spinner
echo -e "${C_GREEN} ✔${C_NC}"

# Финал
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 ГОТОВО!${C_NC}"
echo -e "    Трафик с ${C_GREEN}$LOCAL_IP${C_NC} перенаправлен на ${C_CYAN}$EU_IP${C_NC}"
echo -e "${C_CYAN}================================================${C_NC}\n"

if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DWhiteList"
    FINAL_LINK="vless://${UUID}@${ENTRY_ADDRESS}:${PORT}?${PARAMS}#${NEW_NAME}"
    echo -e "${C_PURPLE}${C_BOLD}👇 ВАША НОВАЯ ССЫЛКА 👇${C_NC}"
    echo -e "${C_GREEN}${FINAL_LINK}${C_NC}\n"
fi
