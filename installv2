#!/bin/bash

# Скрипт установки L2TP/IPsec VPN сервера для Ubuntu 22.04/24.04
# Проверка root прав
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен с правами root" 1>&2
   exit 1
fi

# Генерация случайных значений
PSK_KEY=$(openssl rand -hex 16)
VPN_LOCAL_IP="192.168.42.1"
VPN_IP_RANGE="192.168.42.10-192.168.42.200"
USER_COUNT=5

# Определение внешнего IP адреса
EXTERNAL_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s api.ipify.org)
DEFAULT_IFACE=$(ip -4 route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -1)

# Установка пакетов
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y strongswan libstrongswan-standard-plugins strongswan-libcharon \
    libcharon-extra-plugins xl2tpd ppp iptables-persistent net-tools curl

# Создание пользователей
echo "" > /etc/ppp/chap-secrets
USER_LIST=""
for i in $(seq 1 $USER_COUNT); do
    VPN_USER="vpnuser$i"
    VPN_PASSWORD=$(openssl rand -hex 8)
    echo "$VPN_USER * \"$VPN_PASSWORD\" *" >> /etc/ppp/chap-secrets
    USER_LIST+="Пользователь $i: Логин: $VPN_USER, Пароль: $VPN_PASSWORD\n"
done

# Настройка StrongSwan (IPsec)
cat > /etc/ipsec.conf <<EOF
config setup
    uniqueids=never
    charondebug="ike 2, knl 2, cfg 2"

conn L2TP-IPsec
    auto=add
    keyexchange=ikev1
    authby=secret
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/1701
    ike=aes256-sha256-modp2048,aes128-sha1-modp2048,3des-sha1-modp2048!
    esp=aes256-sha256,aes128-sha1,3des-sha1!
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    fragmentation=yes
EOF

# Установка PSK
cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "$PSK_KEY"
EOF
chmod 600 /etc/ipsec.secrets

# Настройка xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = $VPN_IP_RANGE
local ip = $VPN_LOCAL_IP
require chap = yes
refuse pap = yes
require authentication = yes
name = L2TPVPN
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Настройка PPP
cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
auth
mtu 1400
mru 1400
nodefaultroute
proxyarp
connect-delay 5000
lcp-echo-interval 60
lcp-echo-failure 10
idle 1800
EOF

# Включение IP Forwarding
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/60-vpn.conf
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.d/60-vpn.conf
echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.d/60-vpn.conf
sysctl -p /etc/sysctl.d/60-vpn.conf

# Настройка firewall
iptables -t nat -A POSTROUTING -s $VPN_LOCAL_IP/24 -o $DEFAULT_IFACE -j MASQUERADE
iptables -A INPUT -p udp --dport 1701 -j ACCEPT
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT
iptables -A FORWARD -i $DEFAULT_IFACE -o ppp+ -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ppp+ -o $DEFAULT_IFACE -j ACCEPT
netfilter-persistent save

# Перезапуск сервисов
systemctl restart strongswan-starter
systemctl restart xl2tpd
systemctl enable strongswan-starter
systemctl enable xl2tpd

# Вывод данных для подключения
echo "======================================================"
echo "           L2TP/IPsec VPN сервер настроен!            "
echo "======================================================"
echo "Сервер:         $EXTERNAL_IP"
echo "Pre-Shared Key: $PSK_KEY"
echo ""
echo "Данные для подключения:"
echo -e "$USER_LIST"
echo ""
echo "Справочная информация сохранена в файле ~/vpn-info.txt"
echo "======================================================"

# Сохранение справочной информации
cat > ~/vpn-info.txt <<EOF
==============================================
     L2TP/IPsec VPN сервер настроен!
==============================================

Сервер:         $EXTERNAL_IP
Pre-Shared Key: $PSK_KEY

Данные для подключения:
$(echo -e "$USER_LIST")

Для настройки клиента:
1. Тип VPN: L2TP/IPsec с общим ключом
2. Сервер: $EXTERNAL_IP
3. IPsec Pre-Shared Key: $PSK_KEY
4. Выберите пользователя и введите его логин/пароль

Если возникают проблемы с подключением:
- Убедитесь, что UDP порты 500, 1701 и 4500 открыты
- Проверьте, что ваш провайдер не блокирует VPN-трафик
==============================================
EOF

echo "Установка завершена!"
