#!/system/bin/qjs

import { Base64 } from './modules/base64.js';
import { readFile, writeToFile, execCommand } from './modules/system.js';

const SHADOWSOCKS_CONFIG = '/opt/etc/shadowsocks.json'; // Путь к конфигу Shadowsocks
const SHADOWSOCKS_SERVERS = '/online/shadowsocks/servers'; // Файл со списком серверов
const SHADOWSOCKS_ACTIVE = '/online/shadowsocks/active'; // Файл с индексом активного сервера
const SHADOWSOCKS_DEAMON = '/online/opt/etc/init.d/S22shadowsocks';

const dnsCache = {}; // Кэш для хранения результатов DNS-запросов

// Разрешает доменное имя в IP-адрес, используя кэширование для ускорения повторных запросов
function resolveDomainToIP(domainName) {
    // Проверка на валидный IPv4 адрес
    const ipv4Pattern = /^\d{1,3}(\.\d{1,3}){3}$/;
    if (ipv4Pattern.test(domainName)) {
        print(`Аргумент уже является IP-адресом: ${domainName}`);
        return domainName;
    }
    
    if (dnsCache[domainName]) {
        print(`Кэшированный IP-адрес для ${domainName}: ${dnsCache[domainName]}`);
        return dnsCache[domainName];
    }

    const result = execCommand(`busybox nslookup ${domainName}`, 'r');
    if (result.includes("can't resolve")) {
        print(`Ошибка: не удалось разрешить ${domainName}`);
        return null;
    }

    // Находим начало интересующей нас секции с доменным именем
    const domainSectionIndex = result.indexOf(`Name:      ${domainName}`);
    if (domainSectionIndex === -1) {
        print(`Информация о домене ${domainName} не найдена.`);
        return null;
    }
    const domainSection = result.substring(domainSectionIndex);

    const ipv4Regex = /Address \d+: (\d+\.\d+\.\d+\.\d+)/;
    const match = domainSection.match(ipv4Regex);
    if (match) {
        const ip = match[1];
        print(`IP-адрес для ${domainName} найден: ${ip}`);
        dnsCache[domainName] = ip;
        return ip;
    } else {
        print(`IP-адрес для ${domainName} не найден.`);
        return null;
    }
}

// Разбирает URL Shadowsocks и возвращает его компоненты
function parseShadowsocksUrl(ssUrl) {
    const decoded = Base64.decode(ssUrl.split("//")[1].split("@")[0]);
    const [method, password] = decoded.split(":");
    const [addressPort, description] = ssUrl.split("@")[1].split("#");
    const [address, port] = addressPort.split(":");
    return { method, password, address, port, description: description.trim() };
}

// Читает файл с серверами и возвращает массив строк
function readServersFile(filePath) {
    const content = readFile(filePath);
    return content ? content.split('\n').filter(line => line) : [];
}

// Получает конфигурацию сервера по его индексу
function getConfigServer(servers, activeIndex) {
    const ssUrl = servers[activeIndex];
    return ssUrl ? parseShadowsocksUrl(ssUrl) : null;
}

// Выводит список серверов с описанием
function displayServersName(servers, activeIndex) {
    servers.forEach((ssUrl, index) => {
        const { description } = parseShadowsocksUrl(ssUrl);
        print(activeIndex !== null && parseInt(activeIndex) === index ? `item[#00ee00]:[${description}]:` : `item:${description}:SET ${index}`);
    });
}

// Устанавливает активный конфиг Shadowsocks и перезапускает сервис
function setShadowsocksConfigActive(ssData, index) {
    const ipAddress = resolveDomainToIP(ssData.address);
    if (!ipAddress) {
        print("text: Ошибка 'get IP'");
        return;
    }

    writeToFile(SHADOWSOCKS_ACTIVE, String(index));

    const config = JSON.stringify({
        server: [ipAddress],
        mode: "tcp_and_udp",
        server_port: ssData.port,
        local_address: "0.0.0.0",
        local_port: 1080,
        password: ssData.password,
        timeout: 86400,
        method: ssData.method
    }, null, 4);

    writeToFile(SHADOWSOCKS_CONFIG, config);
    const output = execCommand(`${SHADOWSOCKS_DEAMON} restart`);
    print(output.includes('done.') ? "text: Успешно запущен." : "text: Ошибка при запуске.");
}

function setIptablesRules() {
    const deamon = readFile(SHADOWSOCKS_DEAMON);
    if (deamon.includes('ss-redir')) {

        const config = readFile(SHADOWSOCKS_CONFIG);
        const regex = /\b(?:\d{1,3}\.){3}\d{1,3}\b/g;
        const ip = config.match(regex)[0];

        execCommand(`xtables-multi iptables -t nat -N SHADOWSOCKS`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d ${ip} -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 0.0.0.0/8 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 10.0.0.0/8 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 127.0.0.0/8 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 169.254.0.0/16 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 172.16.0.0/12 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 192.168.0.0/16 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 224.0.0.0/4 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -d 240.0.0.0/4 -j RETURN`);
        execCommand(`xtables-multi iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports 1080`);
        execCommand(`xtables-multi iptables -t nat -I PREROUTING -p tcp -j SHADOWSOCKS`);
    } else {
        execCommand(`xtables-multi iptables -t nat -F SHADOWSOCKS`);
        execCommand(`xtables-multi iptables -t nat -D PREROUTING -p tcp -j SHADOWSOCKS`);
        execCommand(`xtables-multi iptables -t nat -X SHADOWSOCKS`);
    }
}

// Функция для настройки и перезапуска сервиса Shadowsocks в зависимости от выбранного режима работы (ss-local или ss-redir)
function setShadowsockMode(proc) {
    let config = '';
    config += '#!/bin/sh\n\n';
    config += 'ENABLED=yes\n';
    config += 'PROCS=' + proc + '\n';
    config += 'ARGS="-c /opt/etc/shadowsocks.json"\n';
    config += 'PREARGS=""\n';
    config += 'DESC=$PROCS\n';
    config += 'PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n\n';
    config += '[ -z "$(which $PROCS)" ] && exit 0\n';
    config += '. /opt/etc/init.d/rc.func\n';

    writeToFile(SHADOWSOCKS_DEAMON, config);
    execCommand(`chmod 775 ${SHADOWSOCKS_DEAMON}`);

    execCommand(`killall -9 ss-local`);
    execCommand(`killall -9 ss-redir`);
    const output = execCommand(`${SHADOWSOCKS_DEAMON} restart`);
    print(output && output.includes('done.') ? "text: Успешно запущен." : "text: Ошибка при запуске.");

    setIptablesRules();
}

// Главная функция, обрабатывающая аргументы командной строки
function main(args) {
    const servers = readServersFile(SHADOWSOCKS_SERVERS);
    const activeIndex = readFile(SHADOWSOCKS_ACTIVE);

    if (args.length < 2) {
        print(`text[#00cccc]:MODE`);
        const configDeamon = readFile(SHADOWSOCKS_DEAMON);
        if (configDeamon.includes('ss-local')) {
            print(`item[#00ee00]:[Local]:`);
            print(`item:Redir:REDIR`);
        } else {
            print(`item:Local:LOCAL`);
            print(`item[#00ee00]:[Redir]:`);
        }
        print(`text[#00cccc]:SERVER LIST`);
        displayServersName(servers, activeIndex);
        return;
    }

    const command = args[1].toUpperCase();
    if (command === 'SET' && args[2] !== undefined) {
        const index = parseInt(args[2], 10);
        const ssData = getConfigServer(servers, index);
        if (ssData) {
            setShadowsocksConfigActive(ssData, index);
        } else {
            print("text:Конфиг не найден");
        }
    } else if (command === 'LOCAL') {
        setShadowsockMode('ss-local');
    } else if (command === 'REDIR') {
        setShadowsockMode('ss-redir');
    } else if (command === 'BOOT') {
        setIptablesRules();
    } else {
        print(`text:Неизвестная команда ${command}`);
    }
}

main(scriptArgs);
