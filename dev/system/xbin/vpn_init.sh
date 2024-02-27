#!/system/bin/busybox sh

CONFIG_DIR="/online/openvpn"
OVPN_DIR="$CONFIG_DIR/ovpn"
ACTIVE_OVPN_FILE="$CONFIG_DIR/active"
ENABLE_OVPN_RANDOM_FILE="$CONFIG_DIR/random"
OPENVPN="/app/bin/oled_hijack/mod/scripts/openvpn.sh"

MOUNT_DIR="/app/webroot"
VPN_LOG="$CONFIG_DIR/log.txt"
WEB_VPN_LOG="$MOUNT_DIR/httpd_root/vpn.html"

LD_LIBRARY_PATH=/app/lib:/system/lib:/system/lib/glibc:/opt/lib

# Инициализация директорий и файлов
if [[ ! -f "$ACTIVE_OVPN_FILE" ]]; then
    mkdir -p $OVPN_DIR $CONFIG_DIR
    chmod 777 $OVPN_DIR $CONFIG_DIR

    for file in exclusive dot running autorun active random log.txt; do 
        echo 0 > "$CONFIG_DIR/$file"; 
    done
fi

# Добавляем ссылку на лог OPENVPN
if [[ ! -f "$WEB_VPN_LOG" ]]; then
    mount -o remount,rw $MOUNT_DIR
    busybox ln -sf $VPN_LOG $WEB_VPN_LOG
    mount -o remount,ro $MOUNT_DIR
fi

# Получение списка .ovpn файлов, исключая активный файл
OVPN_FILES=$(find $OVPN_DIR -type f -name "*.ovpn" ! -name $(cat "$ACTIVE_OVPN_FILE") -exec basename {} \;)

# Если random равен 1 то выбираем случайный файла и запись его имени в active
if [[ $(cat "$ENABLE_OVPN_RANDOM_FILE") -eq 1 ]]; then
    randomFile=$(echo "$OVPN_FILES" | busybox tr ' ' '\n' | busybox shuf -n 1)
    echo "$randomFile" > "$ACTIVE_OVPN_FILE"
fi

# Запуск VPN
$OPENVPN boot