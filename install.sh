#!/bin/bash

C_CYAN='\033[0;36m'; C_GREEN='\033[0;32m'; C_PURPLE='\033[1;35m'; C_RED='\033[0;31m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'; C_BOLD='\033[1m'

clear
echo -e "${C_CYAN}${C_BOLD}    ____  _____ _        _ __   __"
echo "   |  _ \| ____| |      / \\ \ / /"
echo "   | |_) |  _| | |     / _ \\ V / "
echo "   |  _ <| |___| |___ / ___ \| |  "
echo "   |_| \_\_____|_____/_/   \_\_|  "
echo -e "\n  ✦ Super Relay Auto-Installer v4.3 ✦${C_NC}\n"

# 1. Сбор данных
LOCAL_IP=$(curl -s ifconfig.me || echo "unknown")
echo -e "🔎 Локальный IP: ${C_GREEN}$LOCAL_IP${C_NC}\n"

echo -e "${C_BOLD}Шаг 1: Конфигурация${C_NC}"
echo -e "1) Ссылка vless://\n2) Вручную"
read -p "Выбор: " M
HAS_LINK=false
if [ "$M" == "1" ]; then
    read -p "🔗 Ссылка: " L
    if [[ "$L" == vless://* ]]; then
        HAS_LINK=true
        UUID=$(echo $L | sed -E 's/vless:\/\/([^@]+)@.*/\1/')
        EU_IP=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
        PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
        PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/' || echo "")
        NAME=$(echo $L | sed -E 's/.*#(.*)/\1/' || echo "Relay")
    fi
else
    read -p "🌍 IP Европы: " EU_IP
    read -p "🚪 Порт: " PORT
fi

echo -e "\n${C_BOLD}🚀 Маршрут:${C_NC} [Вы] -> ${C_GREEN}$LOCAL_IP:$PORT${C_NC} -> ${C_CYAN}$EU_IP:$PORT${C_NC}"
read -p "Начать установку? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then exit; fi

read -p "🌐 Домен (если есть, иначе Enter): " ENTRY_ADDR
if [ -z "$ENTRY_ADDR" ]; then ENTRY_ADDR=$LOCAL_IP; fi

# 2. Установка (с выводом ошибок)
echo -e "\n${C_BOLD}➜ Настройка системы...${C_NC}"

# Включаем форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Очистка и установка правил
iptables -t nat -F
for proto in tcp udp; do
    iptables -t nat -A PREROUTING -p $proto --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
    iptables -t nat -A POSTROUTING -p $proto -d $EU_IP --dport $PORT -j MASQUERADE
done

# Установка софта
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx iptables-persistent

# Сохранение правил
netfilter-persistent save

# Финал
echo -e "\n${C_CYAN}================================================${C_NC}"
echo -e "${C_GREEN}${C_BOLD} 🎉 ВСЁ ГОТОВО!${C_NC}"
echo -e "    Трафик порта ${PORT} теперь идет через этот сервер."
echo -e "${C_CYAN}================================================${C_NC}\n"

if [ "$HAS_LINK" = true ]; then
    NEW_NAME="${NAME}%2DWhiteList"
    echo -e "${C_PURPLE}${C_BOLD}👇 ВАША НОВАЯ ССЫЛКА 👇${C_NC}"
    echo -e "${C_GREEN}vless://${UUID}@${ENTRY_ADDR}:${PORT}?${PARAMS}#${NEW_NAME}${C_NC}\n"
fi
