#!/bin/bash

# 1. Сбор данных
echo "--- RELAY CONFIG v4.4 ---"
read -p "VLESS LINK: " L
read -p "DOMAIN (optional): " DOMAIN

# 2. Парсинг (надежный способ)
UUID=$(echo $L | sed -E 's/vless:\/\/([^@]+)@.*/\1/')
EU_IP=$(echo $L | sed -E 's/.*@([^:]+):.*/\1/')
PORT=$(echo $L | sed -E 's/.*:([0-9]+).*/\1/' | cut -d'?' -f1 | cut -d'#' -f1)
PARAMS=$(echo $L | sed -E 's/.*\?(.*)#.*/\1/')
NAME=$(echo $L | sed -E 's/.*#(.*)/\1/')

LOCAL_IP=$(curl -s ifconfig.me)
if [ -z "$DOMAIN" ]; then ENTRY="$LOCAL_IP"; else ENTRY="$DOMAIN"; fi

# 3. Сама установка (без украшательств)
echo "Setting up forwarding for port $PORT..."
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -F
iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE
iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE

echo "Installing Nginx..."
apt-get update && apt-get install -y nginx iptables-persistent

# 4. Вывод результата
echo "-----------------------------------"
echo "SUCCESS!"
echo "New link:"
echo "vless://${UUID}@${ENTRY}:${PORT}?${PARAMS}#${NAME}-WhiteList"
echo "-----------------------------------"
