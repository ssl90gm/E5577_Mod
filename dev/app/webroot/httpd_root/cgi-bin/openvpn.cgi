#!/system/bin/sh

# Обработка GET-запросов с параметрами QUERY_STRING:
#  - dot: Управляет DNS over TLS. "1" - включить, "0" - выключить.
#  - autorun: Автозапуск VPN. "1" - включить, "0" - выключить.
#  - exclusive: Режим VPN-only. "1" - включить, "0" - выключить.
#  - set: Указывает файл конфигурации для VPN-соединения.
#  - connect: Управляет состоянием соединения VPN. "1" - включить, "0" - выключить.
#  - delete: Удаляет файлы конфигурации VPN. "all" - все файлы, другое имя - конкретный файл.

VPN_CONFIG_DIR="/online/openvpn"
OVPN_FILES="$VPN_CONFIG_DIR/ovpn"
VPN_ONLY="$VPN_CONFIG_DIR/exclusive"
VPN_DOT="$VPN_CONFIG_DIR/dot"
VPN_RUN="$VPN_CONFIG_DIR/running"
VPN_AUTORUN="$VPN_CONFIG_DIR/autorun"
ACTIVE_VPN_FILE="$VPN_CONFIG_DIR/active"

OPENVPN="/system/xbin/openvpn.sh"
TTL_CHANGE="/system/bin/ttl"
MAC_CHANGE="/system/xbin/mac_change.sh"
IMEI_CHANGE="/system/xbin/imei_change.sh"
DNS_REDIR="/system/bin/openvpn_scripts/dns-redir.sh"

DNS_OVER_TLS="1.1.1.1"
VPN_RUNNING=0
ROUTE_RESTART=0
VPN_FILE_LISTS="[]"

# Получение IP-адреса VPN
VPN_CLIENT_IP=$(ifconfig tun0 | busybox awk '/inet addr:/{print substr($2,6)}')
VPN_GATEWAY_IP=$(ifconfig tun0 | busybox awk '/P-t-P:/{print substr($2,6)}')

GETS() {
    eval $(echo "$QUERY_STRING" | busybox tr '&' '\n')
    manageActiveOvpnFiles
    manageVpnConnection
    manageVpnDnsOverTls
    removeVpnConfigurations
    createStatusResponse
}

# Обработка POST запросов
POSTS() {
    # Считываем данные POST в переменную
    read -d '' -n "$CONTENT_LENGTH" POST_DATA

    # Получаем имя файла
    FILENAME=$(echo "$POST_DATA" | grep -o 'filename="[^"]*' | grep -o '[^"]*$')

    # Если имя файла не найдено, завершаем скрипт
    if [[ -z "$FILENAME" ]]; then
        echo "Ошибка: файл не загружен."
        exit 1
    fi

    # Удаление части до начала содержимого файла
    FILE_CONTENT=$(echo "$POST_DATA" | busybox sed '1,/^\r$/d')

    # Удаление последних строк после окончания содержимого файла
    FILE_CONTENT=$(echo "$FILE_CONTENT" | busybox sed '/^----------*/,$d')

    # Сохраняем файл
    echo "$FILE_CONTENT" >"$OVPN_FILES/$FILENAME"

    # Отправка HTTP-заголовков и сообщения об успешной загрузке
    echo -e "200 OK HTTP/1.1\r\n\
Access-Control-Allow-Origin: *\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
Connection: close\r\n"

    echo "Файл '$FILENAME' успешно сохранен."
    exit 0
}

# Удаляет указанные файлы конфигурации VPN или все файлы, если указано "all".
removeVpnConfigurations() {
    if [[ ! -z "$delete" ]]; then
        if [[ "$delete" == "all" ]]; then
            echo 0 >$ACTIVE_VPN_FILE
            rm -rf $OVPN_FILES/*
        else
            rm -f "$OVPN_FILES/$delete"
            if [[ $(cat "$ACTIVE_VPN_FILE") == $delete ]]; then
                echo 0 >"$ACTIVE_VPN_FILE"
            fi
        fi
    fi
}

# Управляет адаптивным DNS на основе параметров.
manageVpnDnsOverTls() {
    if [[ -n "$dot" ]] && [[ "$dot" -eq 0 || "$dot" -eq 1 ]]; then
        echo $dot >"$VPN_DOT"
        if [[ "$dot" -eq 0 ]]; then
            $DNS_REDIR 0 >/dev/null 2>&1
            $OPENVPN restart
        elif [[ "$dot" -eq 1 ]]; then
            $DNS_REDIR $DNS_OVER_TLS >/dev/null 2>&1
            $OPENVPN restart
        fi
    fi
}

# Управляет активными файлами конфигурации OpenVPN.
manageActiveOvpnFiles() {
    # Формируем JSON-список из имен файлов .ovpn
    VPN_FILE_LISTS=$(
        find "$OVPN_FILES" \
            -type f \
            -name "*.ovpn" \
            -exec basename {} \; |
            busybox awk '
			BEGIN{ORS="";print "["}
			{printf "\"%s\", ", $0, 1}
			END{print "]"}
			' |
            busybox sed 's/, \]/]/'
    )

    # Обновляем ACTIVE_VPN_FILE, если необходимо
    local ACTIVE_FILE=$(cat "$ACTIVE_VPN_FILE")
    if [[ "$VPN_FILE_LISTS" != "[]" ]] && [[ "$ACTIVE_FILE" = "0" ]]; then
        local FIRST_FILE=$(echo "$VPN_FILE_LISTS" | busybox cut -d '"' -f 2)
        echo "$FIRST_FILE" >$ACTIVE_VPN_FILE
    elif [[ "$VPN_FILE_LISTS" = "[]" ]] && [[ "$ACTIVE_FILE" != "0" ]]; then
        echo 0 >$ACTIVE_VPN_FILE
    fi
}

# Управляет VPN-соединением, включая автозапуск и режим VPN-only.
manageVpnConnection() {
    [[ -n "$autorun" ]] && echo "$autorun" >$VPN_AUTORUN

    # kill-switch vpn on/off
    if [[ -n "$exclusive" && "$exclusive" -eq 1 ]]; then
        echo "$exclusive" >$VPN_ONLY
        $OPENVPN only_on
    elif [[ -n "$exclusive" && "$exclusive" -eq 0 ]]; then
        echo "$exclusive" >$VPN_ONLY
        $OPENVPN only_off
    fi

    # Установка статуса работы VPN
    VPN_RUNNING=$([[ -n "$VPN_CLIENT_IP" ]] && echo 1 || echo 0)

    local VPN_RESTART=0
    local CURRENT_VPN_FILE=$(cat "$ACTIVE_VPN_FILE")

    # Проверка необходимости обновления конфигурации VPN
    if [[ -n "$set" && "$CURRENT_VPN_FILE" != "$set" ]]; then
        $OPENVPN only_off
        echo "$set" >"$ACTIVE_VPN_FILE"
        VPN_RESTART=1
    fi

    # Управление VPN соединением
    if [[ "$VPN_RUNNING" -eq 1 && "$VPN_RESTART" -eq 1 ]]; then
        $OPENVPN restart
    elif [[ -n "$connect" ]] && [[ "$connect" -eq 1 ]]; then
        echo 1 >$VPN_RUN
        if [[ $VPN_RUNNING -eq 0 || $VPN_RESTART -eq 1 ]]; then
            $OPENVPN restart
        fi
    elif [[ -n "$connect" ]] && [[ "$connect" -eq 0 ]]; then
        echo 0 >$VPN_RUN
        $OPENVPN stop
        VPN_RUNNING=0
    fi
}

# Создаёт и отправляет ответ с текущим статусом системы.
createStatusResponse() {
    local VPN_AUTORUN=$([[ $(cat $VPN_AUTORUN) -eq 1 ]] && echo "true" || echo "false")
    local VPN_EXCLUSIVE_MODE=$([[ $(cat $VPN_ONLY) -eq 1 ]] && echo "true" || echo "false")
    local VPN_STATUS=$([[ $VPN_RUNNING -eq 1 ]] && echo "true" || echo "false")
    local VPN_RUN_STATUS=$([[ $(cat $VPN_RUN) -eq 1 ]] && echo "true" || echo "false")
    local VPN_DOT_STATUS=$([[ $(cat $VPN_DOT) -eq 1 ]] && echo "true" || echo "false")

    VPN_PROCESS=false
    if busybox pgrep openvpn >/dev/null; then
        VPN_PROCESS=true 
    fi

    echo -e "200 OK HTTP/1.1\r\n\
Access-Control-Allow-Origin: *\r\n\
Content-Type: application/json; charset=utf-8\r\n\
Connection: close\r\n"

    echo "{
    \"on\": $VPN_RUN_STATUS,
    \"dot\": $VPN_DOT_STATUS,
    \"auto\": $VPN_AUTORUN,
    \"exclusive\": $VPN_EXCLUSIVE_MODE,
    \"connect\": $VPN_STATUS,
    \"running\": $VPN_PROCESS,
    \"active_file\": \"$(cat $ACTIVE_VPN_FILE)\",
    \"files\": $VPN_FILE_LISTS,		
    \"client_ip\": \"$VPN_CLIENT_IP\",
    \"gateway_ip\": \"$VPN_GATEWAY_IP\"
}"
}

[[ "$REQUEST_METHOD" = "GET" ]] && GETS
[[ "$REQUEST_METHOD" = "POST" ]] && POSTS
