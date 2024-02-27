#!/system/bin/qjs

import * as os from 'os';
import * as std from 'std';
import { readFile, writeToFile, execCommand } from './modules/system.js';


const VPN_CONFIG_DIR = "/online/openvpn"; // Директория конфигураций VPN
const VPN_LOG_FILE = `${VPN_CONFIG_DIR}/log.txt`; // Файл логов VPN
const ACTIVE_VPN_FILE = `${VPN_CONFIG_DIR}/active`; // Файл с активной конфигурацией VPN
const VPN_CLIENT_OVPN = `${VPN_CONFIG_DIR}/client.ovpn`; // Файл для сгенерированной конфигурации клиента OpenVPN
const VPN_EXCLUSIVE_MODE = `${VPN_CONFIG_DIR}/exclusive`; // Файл для определения эксклюзивного режима VPN
const VPN_RUN = `${VPN_CONFIG_DIR}/running`; // Файл состояния работы VPN
const VPN_AUTORUN = `${VPN_CONFIG_DIR}/autorun`; // Файл для автоматического запуска VPN при старте системы
const SHADOWSOCKS_CONFIG = '/opt/etc/shadowsocks.json'; // Конфигурационный файл Shadowsocks
const UP = '/system/xbin/openvpn.up'; // Скрипт после установки VPN-соединения
const DOWN = '/system/xbin/openvpn.down'; // Скрипт при разрыве VPN-соединения

const DNS_SERVER = "1.1.1.1";
const DNS_OVER_TLS = '/system/bin/openvpn_scripts/dns-redir.sh';//

// Получение конфигурации Shadowsocks из файла
function getSSConfig() {
    const ssConfigRaw = readFile(SHADOWSOCKS_CONFIG)?.trim();
    const ssConfig = JSON.parse(ssConfigRaw);
    if (!ssConfig) return false;
    const ip = Array.isArray(ssConfig.server) ? ssConfig.server[0] : ssConfig.server;
    const port = ssConfig.server_port.toString();
    return { ip, port };
}

// Модификация правил iptables
function modifyIptables(isEnable) {
    // Извлечение IP и порта для VPN и Shadowsocks
    const activeVpnName = readFile(ACTIVE_VPN_FILE)?.trim();
    const vpnConfigPath = `${VPN_CONFIG_DIR}/ovpn/${activeVpnName}`;
    const vpnConfig = readFile(vpnConfigPath);
    if (!vpnConfig) {
        print('Не удалось прочитать конфигурацию VPN');
        return;
    }

    // 
    const vpnIp = vpnConfig.match(/remote\s+(\S+)/)?.[1];
    const vpnPort = vpnConfig.match(/remote\s+\S+\s+(\d+)/)?.[1];
    const ss = getSSConfig();

    if (!vpnIp || !vpnPort || !ss) {
        print('Не удалось извлечь настройки сети');
        return;
    }

    const iptAction = isEnable ? '-A' : '-D';
    const policyAction = isEnable ? 'DROP' : 'ACCEPT';

    // Команды для настройки/снятия правил iptables
    const commands = [
        `/system/bin/xtables-multi iptables -P OUTPUT ${policyAction}`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -o lo`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -o br0`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -d ${vpnIp} -o wan0 -p tcp -m tcp --dport ${vpnPort}`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -d ${vpnIp} -o wan0 -p udp -m udp --dport ${vpnPort}`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -o tun+`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -d ${ss.ip} -o wan0 -p tcp -m tcp --dport ${ss.port}`,
        `/system/bin/xtables-multi iptables ${iptAction} OUTPUT -j ACCEPT -d ${ss.ip} -o wan0 -p udp -m udp --dport ${ss.port}`
    ];

    // Выполнение команд
    commands.forEach(command => execCommand(command));
    os.sleep(1);
}

// Создание конфигурационного файла OpenVPN
function createOvpnConfig() {
    const activeOvpnName = readFile(ACTIVE_VPN_FILE)?.trim();
    const ovpnConfigPath = `${VPN_CONFIG_DIR}/ovpn/${activeOvpnName}`;
    let ovpnConfig = readFile(ovpnConfigPath);
    if (!ovpnConfig) return;

    const ss = getSSConfig();

    // Формирование конфигурации
    let filteredContent = ovpnConfig.split('\n').filter(line => {
        // Удаляем строки, начинающиеся на # или ;
        if (line.startsWith('#') || line.startsWith(';')) return false;
        // Удаляем строки с указанными ключевыми словами
        if (/^\s*(verb|ping|user|group|keepalive|route-delay|persist-tun|persist-key|ping-restart|route-method|ping-timer-rem|script-security|setenv opt block-outside-dns)\s/.test(line)) return false;
        return true;
    }).join('\n');

    filteredContent += `\nsocks-proxy 127.0.0.1 1080\nroute ${ss.ip} 255.255.255.255 net_gateway\n`;
    writeToFile(VPN_CLIENT_OVPN, filteredContent);
}

// Запуск OpenVPN с текущей конфигурацией
function startOpenvpn() {
    stopOpenvpn();

    const exclusive = readFile(VPN_EXCLUSIVE_MODE);
    if (exclusive && parseInt(exclusive) === 1) {
        modifyIptables(true);
    }
    
    //execCommand(`${DNS_OVER_TLS} ${DNS_SERVER}`);

    createOvpnConfig();
    const output = execCommand(`/opt/sbin/openvpn --daemon --verb 1 --ping 5 --auth-nocache --ping-restart 10 --connect-retry 10 --script-security 2 --up-restart --tmp-dir ${VPN_CONFIG_DIR} --up ${UP} --down ${DOWN} --log ${VPN_LOG_FILE} --config ${VPN_CLIENT_OVPN}`);
    print('text:' + output);
    writeToFile(VPN_LOG_FILE, '<pre>');
    writeToFile(VPN_RUN, "1");
}

// Остановка OpenVPN
function stopOpenvpn() {
    modifyIptables(false);
    execCommand('killall -9 openvpn');
    writeToFile(VPN_LOG_FILE, 'vpn stoping');
    writeToFile(VPN_RUN, "0");
}

// Вывод списка доступных конфигураций VPN
function listOvpls() {
    const activeOvpnName = readFile(ACTIVE_VPN_FILE)?.trim();
    let files = os.readdir(`${VPN_CONFIG_DIR}/ovpn`);
    files = files[0].filter(file => file.endsWith('.ovpn'));
    files.forEach(file => {
        print(activeOvpnName == file ? `item[#00ee00]:[${file}]:` : `item:${file}:set ${file}`);
    });
}

// Установка активной конфигурации VPN и запуск
function setActiveOvpn(fileName) {
    execCommand('killall -9 openvpn');
    modifyIptables(false);
    writeToFile(ACTIVE_VPN_FILE, fileName);
    writeToFile(VPN_LOG_FILE, '');
    startOpenvpn();
    writeToFile(ACTIVE_VPN_FILE, fileName);
    print(`text:Set ${fileName} success`);
}

// Проверка запущен ли openvpn
function checkVpnRunning() {
    const command = `busybox ps | busybox grep openvpn`;
    const process = std.popen(command, "r");
    const output = process.readAsString();
    process.close();
    return output.includes('openvpn --daemon');
}


// Основная функция обработки команд
function main(args) {
    // Проверка флага автостарт при загрузке системы
    const autorunState = readFile(VPN_AUTORUN);
    const autorun = autorunState && parseInt(autorunState) === 1;

    // Прокерка флага блокировки всего трафика кроме VPN
    const exclusiveState = readFile(VPN_EXCLUSIVE_MODE);
    const exclusive  = exclusiveState && parseInt(exclusiveState) === 1;

    if (args.length < 2) {
        // Вывод информации о текущем состоянии VPN
        print('text[#00cccc]:RUNNING');
        const running = checkVpnRunning();
        print(running ? 'item[#00ee00]:[Enable]' : 'item:Enable:start');
        print(running ? 'item:Disable:STOP' : 'item[#ee0000]:[Disable]');       
        // Вывод информации о настройках VPN автостарта
        print('text[#00cccc]:AUTORUN');
        print(autorun ? 'item[#00ee00]:[Enable]' : 'item:Enable:autorun');
        print(autorun ? 'item:Disable:autorun_off' : 'item[#ee0000]:[Disable]');
        // Вывод информации об эксклюзивном режыме (толька vpn)
        print('text[#00cccc]:EXCLUSIVE MODE');
        print(exclusive ? 'item[#00ee00]:[Enable]' : 'item:Enable:exclusive');
        print(exclusive ? 'item:Disable:exclusive_off' : 'item[#ee0000]:[Disable]');
        // Вывод списка конфигураций VPN
        print('text[#00cccc]:OVPN CONFIGS');
        listOvpls();
        return;
    }

    // Обработка команд
    switch (args[1].toUpperCase()) {
        case 'SET':
            setActiveOvpn(args[2]);
            break;
        case 'START':
            startOpenvpn();
            print('text:VPN включен');
            break;
        case 'STOP':
            stopOpenvpn();
            print('text:VPN отключен');
            break;
        case 'BOOT':
            autorun && startOpenvpn();
            break;
        case 'RESTART':
            stopOpenvpn();
            os.sleep(2);
            startOpenvpn();
            break;
        case 'ONLY_ON':
            modifyIptables(true);
            break;
        case 'ONLY_OFF':
            modifyIptables(false);
            break;
        case 'AUTORUN':
            writeToFile(VPN_AUTORUN, '1');
            print('text:Запуск при старте включен');
            break;
        case 'AUTORUN_OFF':
            writeToFile(VPN_AUTORUN, '0');
            print('text:Запуск при старте отключен');
            break;
        case 'EXCLUSIVE':
            writeToFile(VPN_EXCLUSIVE_MODE, '1');
            print('text:Значение успешно установлено');
            break;
        case 'EXCLUSIVE_OFF':
            writeToFile(VPN_EXCLUSIVE_MODE, '0');
            print('text:Значение успешно сброшено');
            break;
        default:
            print(`text:Unknown command: ${args[1]}`);
            break;
    }
}


main(scriptArgs);
