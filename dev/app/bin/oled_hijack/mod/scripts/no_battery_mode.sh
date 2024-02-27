#!/system/bin/qjs

import { readFile, writeToFile, execCommand } from './modules/system.js';

const CONF_FILE = "/var/battery_status";

function getBatteryData() {
    const cache = readFile(CONF_FILE);
    if(cache !== null) return cache;

    const result = execCommand("atc 'AT^NVRD=50364'");
    const batteryData = (result.match(/NVRD.*[0-9 ]{11}/g) || []).map(match => match.match(/[0-9 ]{11}/)[0]);
    const state = batteryData.includes("00 00 00 00") ? "1" : "0";
    writeToFile(CONF_FILE, state);
    return state;
}

function setBatteryData(enable) {
    const command = enable ? 'atc "AT^NVWR=50364,04,00 00 00 00"' : 'atc "AT^NVWR=50364,04,01 01 00 00"';
    const result = execCommand(command);
    if (result.includes("OK")) {
        writeToFile(CONF_FILE, enable ? "1" : "0");
        return true;
    }
    return false;
}

function main(args) {
    if (args.length < 2) {
        print("text[#00cccc]:РАБ. БЕЗ БАТАРЕИ");
        print("text[#cccccc]:~~~~~~~~~~~~~~~~~~~~");
        const batteryState = getBatteryData();
        if(batteryState === "0") {
            print(`item[#00ee00]:<Включена>:`);
            print(`item: Выключить:DISABLE`);
        } else {
            print(`item: Включить:ENABLE`);
            print(`item[#ee5555]:<Выключена>:`);
        }
        return;
    }
	
    const command = args[1];
    switch (command) {
        case 'ENABLE':
            if (setBatteryData(false)) {
                print("text:Батарея отключена");
            } else {
                print("text:Ошибка");
            }
            break;
        case 'DISABLE':
            if (setBatteryData(true)) {
                print("text:Батарея подключена");
            } else {
                print("text:Ошибка");
            }
            break;
        default:
            print(`text:Неизвестная команда ${command}`);
            break;
    }
}

main(scriptArgs);
