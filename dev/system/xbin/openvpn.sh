#!/system/bin/busybox sh

SS_IP="138.199.27.206"
SS_PORT="11270"

OVPN_FILES="/online/openvpn/ovpn"
FTP_DIR="$OVPN_FILES"

VPN_CONFIG_DIR="/online/openvpn"
VPN_EXCLUSIVE_MODE="$VPN_CONFIG_DIR/exclusive"
VPN_RUN="$VPN_CONFIG_DIR/running"
VPN_AUTORUN="$VPN_CONFIG_DIR/autorun"
ACTIVE_VPN_FILE="$VPN_CONFIG_DIR/active"
VPN_LOG_FILE=$VPN_CONFIG_DIR/log.txt
VPN_CLIENT_OVPN="$VPN_CONFIG_DIR/client.ovpn"

OPENVPN_SCRIPTS="/system/xbin"
UP="$OPENVPN_SCRIPTS/openvpn.up"
DOWN="$OPENVPN_SCRIPTS/openvpn.down"

LD_LIBRARY_PATH=/app/lib:/system/lib:/system/lib/glibc:/opt/lib

dnsOverTlsSystem() {
    /etc/dns_over_tls.sh $(cat "/data/userdata/dns_over_tls")
}

create_ovpn() {
    local ACTIVE_OVPN=$(cat "$ACTIVE_VPN_FILE")
    if [[ -f "$OVPN_FILES/$ACTIVE_OVPN" ]]; then
        sed -e '/^#/d' \
            -e '/^;/d' \
            -e '/^\(verb\|ping\|user\|group\|keepalive\|route-delay\|persist-tun\|persist-key\|ping-restart\|route-method\|ping-timer-rem\|script-security\|setenv opt block-outside-dns\)\s/d' \
            "$OVPN_FILES/$ACTIVE_OVPN" >"$VPN_CLIENT_OVPN"

        # Добавляем socks-proxy и route в конец файла для работы через shadowsocks
        echo "socks-proxy 127.0.0.1 1080" >>"$VPN_CLIENT_OVPN"
        echo "route $SS_IP 255.255.255.255 net_gateway" >>"$VPN_CLIENT_OVPN"
    fi
}

onKillSwitch() {
    local OVPN_FILE=$(cat "$ACTIVE_VPN_FILE")

    # Извлечение IP-адреса и порта из активного файла .ovpn
    local OVPN_IP=$(awk '/^remote/ {print $2}' "$OVPN_FILES/$OVPN_FILE")
    local OVPN_PORT=$(awk '/^remote/ {print $3}' "$OVPN_FILES/$OVPN_FILE")

    # Настройка правил iptables
    local IPT_CMD="xtables-multi iptables"
    $IPT_CMD -P OUTPUT DROP
    $IPT_CMD -A OUTPUT -j ACCEPT -o lo
    $IPT_CMD -A OUTPUT -j ACCEPT -o br0
    $IPT_CMD -A OUTPUT -j ACCEPT -d $OVPN_IP -o wan0 -p tcp -m tcp --dport $OVPN_PORT
    $IPT_CMD -A OUTPUT -j ACCEPT -d $OVPN_IP -o wan0 -p udp -m udp --dport $OVPN_PORT
    $IPT_CMD -A OUTPUT -j ACCEPT -o tun+

    # Shadowsock server ip and port
    $IPT_CMD -A OUTPUT -j ACCEPT -d $SS_IP -o wan0 -p tcp -m tcp --dport $SS_PORT
    $IPT_CMD -A OUTPUT -j ACCEPT -d $SS_IP -o wan0 -p udp -m udp --dport $SS_PORT

    sleep 1
}

offKillSwitch() {
    local OVPN_FILE=$(cat "$ACTIVE_VPN_FILE")
    
    # Извлечение IP-адреса и порта из активного файла .ovpn
    local OVPN_IP=$(awk '/^remote/ {print $2}' "$OVPN_FILES/$OVPN_FILE")
    local OVPN_PORT=$(awk '/^remote/ {print $3}' "$OVPN_FILES/$OVPN_FILE")

    # Настройка правил iptables
    local IPT_CMD="xtables-multi iptables"
    $IPT_CMD -P OUTPUT ACCEPT
    $IPT_CMD -D OUTPUT -j ACCEPT -o lo
    $IPT_CMD -D OUTPUT -j ACCEPT -o br0
    $IPT_CMD -D OUTPUT -j ACCEPT -d $OVPN_IP -o wan0 -p tcp -m tcp --dport $OVPN_PORT
    $IPT_CMD -D OUTPUT -j ACCEPT -d $OVPN_IP -o wan0 -p udp -m udp --dport $OVPN_PORT
    $IPT_CMD -D OUTPUT -j ACCEPT -o tun+

    # Shadowsock server ip and port
    $IPT_CMD -D OUTPUT -j ACCEPT -d $SS_IP -o wan0 -p tcp -m tcp --dport $SS_PORT
    $IPT_CMD -D OUTPUT -j ACCEPT -d $SS_IP -o wan0 -p udp -m udp --dport $SS_PORT

    sleep 1
}

start_openvpn() {
    if [[ $(cat "$VPN_EXCLUSIVE_MODE") -eq 1 ]]; then
        offKillSwitch
        onKillSwitch
    fi

    create_ovpn
    /opt/sbin/openvpn --daemon --verb 1 --ping 5 --auth-nocache --ping-restart 10 --connect-retry 10 --script-security 2 --up-restart --tmp-dir $VPN_CONFIG_DIR --up $UP --down $DOWN --log $VPN_LOG_FILE --config $VPN_CONFIG_DIR/client.ovpn

    echo '<pre>' >>$VPN_LOG_FILE
}

stop_openvpn() {
    killall openvpn
    sleep 2
    dnsOverTlsSystem >/dev/null 2>&1
    echo "vpn stopping" >$VPN_LOG_FILE
}

restart_openvpn() {
    stop_openvpn
    start_openvpn
}

case "$1" in
"stop")
    stop_openvpn
    ;;
"start")
    start_openvpn
    ;;
"boot")
    if [[ $(cat "$VPN_AUTORUN") -eq 1 ]]; then
        start_openvpn
    fi
    ;;
"restart")
    restart_openvpn
    ;;
"only_on")
    onKillSwitch
    ;;
"only_off")
    offKillSwitch
    ;;
"only_off")
    offKillSwitch
    ;;
esac
