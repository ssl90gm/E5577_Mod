#!/system/bin/busybox sh

IMEI_SET_COMMAND='AT^PHYNUM=IMEI'
IMEI_GENERATOR="/app/bin/oled_hijack/imei_generator"
CURRENT_IMEI_FILE="/var/current_imei"
BACKUP_IMEI_FILE="/online/imei_backup"

CONF_TTL_FILE="/data/userdata/fix_ttl"
CURRENT_TTL_MODE="$(cat $CONF_TTL_FILE)"
FIX_TTL="/system/etc/fix_ttl.sh"

# IMEI caching to prevent menu slowdowns
if [[ ! -f "$CURRENT_IMEI_FILE" ]]; then
    CURRENT_IMEI=$(atc 'AT+CGSN' | grep -o '[0-9]\{15\}')
    echo $CURRENT_IMEI > $CURRENT_IMEI_FILE
else
    CURRENT_IMEI=$(cat $CURRENT_IMEI_FILE)
fi

if [[ "$CURRENT_IMEI" == "" ]]; then
    CURRENT_IMEI=$(atc 'AT+CGSN' | grep -o '[0-9]\{15\}')
    echo $CURRENT_IMEI > $CURRENT_IMEI_FILE
fi

# save backup
[[ ! -f $BACKUP_IMEI_FILE ]] && echo $CURRENT_IMEI > $BACKUP_IMEI_FILE

change_imei () {
    local IMEI="$1"
    if atc "$IMEI_SET_COMMAND,$IMEI" | grep "OK"; then
        echo "text[#7777ee]:Success"
        echo "text:NEW: $IMEI"
        echo "$IMEI" > "$CURRENT_IMEI_FILE"
    else
        echo "text[#ee5555]:Failed"
    fi
}

CURRENT_IMEI_CUT="$(echo $CURRENT_IMEI | cut -c 1-8)"

change_ttl() {
    TTL=$1
    echo $TTL > $CONF_TTL_FILE
    $FIX_TTL 2
    echo "text[#7777ee]:Success"
    echo "text:NEW TTL=$TTL"
}

case "$1" in
    "")
        # IMEI 
        echo "text[#00cccc]:IMEI "
        echo "text[#cccccc]:$CURRENT_IMEI"
        echo "text[#cccccc]:~~~~~~~~~~~~~~~~~~~~"
        if [[ "$CURRENT_IMEI_CUT" != "35428207" ]] && [[ "$CURRENT_IMEI_CUT" != "35365206" ]]; then
            echo "item[#00ee00]:Stock"
        else
            echo "item:Stock:0"
        fi
        if [[ "$CURRENT_IMEI_CUT" == "35428207" ]]; then
            echo "item[#00ee00]:Random Android"
        else
            echo "item:Random Android:1"
        fi
        if [[ "$CURRENT_IMEI_CUT" == "35365206" ]]; then
            echo "item[#00ee00]:Random WinPhone"
        else
            echo "item:Random WinPhone:2"
        fi
        
        echo "pagebreak:"

        # TTL
        echo "text[#00cccc]:TTL FIX"
        echo "text[#cccccc]:Current TTL=$CURRENT_TTL_MODE"
        echo "text[#cccccc]:~~~~~~~~~~~~~~~~~~~~"
        if [[ "$CURRENT_TTL_MODE" == "" ]] || [[ "$CURRENT_TTL_MODE" == "0" ]]; then
            echo "item[#EE7777]:[Disabled]"
        else
            echo "item:Disabled:TTL 0"
        fi
        if [[ "$CURRENT_TTL_MODE" == "64" ]]; then
            echo "item[#00ee00]:[TTL=64]"
        else
            echo "item:TTL=64:TTL 64"
        fi
        if [[ "$CURRENT_TTL_MODE" == "65" ]]; then
            echo "item[#00ee00]:[TTL=65]"
        else
            echo "item:TTL=65:TTL 65"
        fi
        if [[ "$CURRENT_TTL_MODE" == "128" ]]; then
            echo "item[#00ee00]:[TTL=128]"
        else
            echo "item:TTL=128:TTL 128"
        fi
        ;;
    "0")
        IMEI_BACKUP="$(cat $BACKUP_IMEI_FILE)"
        [[ "$IMEI_BACKUP" == "" ]] && exit 253
        change_imei $IMEI_BACKUP
        ;;
    "1")
        IMEI_ANDROID="$($IMEI_GENERATOR -m 35428207)"
        change_imei $IMEI_ANDROID
        ;;
    "2")
        IMEI_WINPHONE="$($IMEI_GENERATOR -m 35365206)"
        change_imei $IMEI_WINPHONE
        ;;
    "TTL")
        change_ttl $2
        ;;
esac
