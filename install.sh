#!/bin/bash

# Генерация случайных значений
PSK_KEY=$(openssl rand -hex 16)
VPN_LOCAL_IP="192.168.1.1"
VPN_IP_RANGE="192.168.1.100-192.168.1.200"

# Определяем выходной интерфейс
DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk '{print $5}' | head -1)

# Убедимся, что директория /etc/ppp существует
mkdir -p /etc/ppp

# Создание 10 пользователей
USER_COUNT=10
echo "" > /etc/ppp/chap-secrets
USER_LIST=""
for i in $(seq 1 $USER_COUNT); do
    VPN_USER="vpnuser$i"
    VPN_PASSWORD=$(openssl rand -hex 8)
    echo "$VPN_USER L2TPVPN \"$VPN_PASSWORD\" *" >> /etc/ppp/chap-secrets
    USER_LIST+="Пользователь $i: Логин: $VPN_USER, Пароль: $VPN_PASSWORD\n"
done

# Обновление и установка пакетов
sudo apt update -y && sudo apt install -y strongswan xl2tpd ppp iptables

# Настройка IPsec
cat > /etc/ipsec.conf <<EOF
config setup
    uniqueids=never

conn L2TP-IPsec
    auto=add
    keyexchange=ikev1
    authby=secret
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/1701
    ike=aes256-sha1-modp1024
    esp=aes256-sha1
    dpdaction=clear
EOF

# Запись Pre-Shared Key
echo ": PSK \"$PSK_KEY\"" > /etc/ipsec.secrets

# Настройка xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = $VPN_IP_RANGE
local ip = $VPN_LOCAL_IP
refuse pap = yes
require authentication = yes
name = L2TPVPN
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Настройка PPP
cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
auth
mtu 1400
mru 1400
nodefaultroute
lock
proxyarp
connect-delay 5000
EOF

# Включение IP Forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Настройка NAT
iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
iptables -A FORWARD -i ppp+ -o $DEFAULT_IFACE -j ACCEPT
iptables -A FORWARD -i $DEFAULT_IFACE -o ppp+ -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables-save > /etc/iptables.rules
echo "pre-up iptables-restore < /etc/iptables.rules" >> /etc/network/interfaces

# Установка маршрута по умолчанию
ip route add default via $(ip route get 8.8.8.8 | awk '{print $3}' | head -1) dev $DEFAULT_IFACE || true

# Перезапуск сервисов
systemctl restart strongswan-starter
systemctl restart xl2tpd
systemctl enable strongswan-starter xl2tpd

# Вывод данных для подключения
echo "========================="
echo "L2TP/IPsec VPN настроен!"
echo "Сервер: $(curl -s ifconfig.me)"
echo "Pre-Shared Key (PSK): $PSK_KEY"
echo -e "$USER_LIST"
echo "========================="
