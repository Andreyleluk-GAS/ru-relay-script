#!/bin/bash

# Цвета для красивого вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Без цвета

echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}🚀 Super Relay Auto-Installer (VLESS / 3X-UI) 🚀${NC}"
echo -e "${BLUE}================================================${NC}"

# Проверка на права root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ошибка: Запустите скрипт с правами root (например: sudo bash script.sh)${NC}"
  exit 1
fi

# Запрос данных у пользователя
read -p "🌍 Введите IP адрес ЕВРОПЕЙСКОГО сервера (куда шлем трафик): " EU_IP
read -p "🚪 Введите ПОРТ (например, 8443): " PORT

echo -e "\n${BLUE}⚙️  Настраиваем маршрутизацию на уровне ядра...${NC}"

# Включаем форвардинг IPv4
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Очищаем старые правила для этого порта (защита от дублей)
iptables -t nat -D PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
iptables -t nat -D POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null
iptables -t nat -D PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT 2>/dev/null
iptables -t nat -D POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE 2>/dev/null

# Применяем новые правила (TCP + UDP)
iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p tcp -d $EU_IP --dport $PORT -j MASQUERADE
iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $EU_IP:$PORT
iptables -t nat -A POSTROUTING -p udp -d $EU_IP --dport $PORT -j MASQUERADE

echo -e "${BLUE}💾 Устанавливаем компоненты и сохраняем правила...${NC}"
apt-get update -qq
# Тихая установка iptables-persistent без вывода синих окон
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent > /dev/null
netfilter-persistent save > /dev/null

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}✅ ГОТОВО! Магия произошла.${NC}"
echo -e "   -> Весь трафик порта ${PORT} перенаправляется на ${EU_IP}:${PORT}"
echo -e "${RED}⚠️  ВАЖНО: Убедитесь, что порт ${PORT} открыт в Firewall Яндекс Клауда!${NC}"
echo -e "${GREEN}================================================${NC}"
