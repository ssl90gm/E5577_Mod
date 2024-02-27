#!/system/bin/busybox sh

CONF_FILE="/data/userdata/dns_over_tls"
CURRENT_MODE="$(cat $CONF_FILE)"

case "$1" in
"")
    echo "text[#00cccc]:DNS-OVER-TLS"
    echo "text[#cccccc]:~~~~~~~~~~~~~~~~~~~~"

    if [[ "$CURRENT_MODE" == "" || "$CURRENT_MODE" == "0" ]]; then
        echo "item[#ee0000]:[Disabled]"
    else
        echo "item:Disabled:0"
    fi

    if [[ "$CURRENT_MODE" == "1" ]]; then
        echo "item[#00ee00]:[Enabled]"
    else
        echo "item:Enabled:1"
    fi

    if [[ "$CURRENT_MODE" == "2" ]]; then
        echo "item[#00ee00]:[Enabled + adblock]"
    else
        echo "item:Enabled + adblock:2"
    fi
    ;;
"0")
    echo "0" >$CONF_FILE && /etc/dns_over_tls.sh 0
    echo "text[#7777ee]:Success"
    ;;
"1")
    echo "1" >$CONF_FILE && /etc/dns_over_tls.sh 1
    echo "text[#7777ee]:Success"
    ;;
"2")
    echo "2" >$CONF_FILE && /etc/dns_over_tls.sh 2
    echo "text[#7777ee]:Success"
    ;;
esac