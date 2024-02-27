#!/system/bin/qjs

import { fromXML } from './modules/from-xml.js';
import { fileExists, readFile, execCommand } from './modules/system.js';

const SMS_WEBHOOK_CLIENT = "/app/bin/oled_hijack/mod/sms_webhook_client";
const USSD_XML = "/data/userdata/ussd/ussd_cmd_list.xml";
const DEFAULT_USSD_FILE = `<config>
  <USSD_command>
    <Name>Баланс</Name>
    <Command>*100#</Command>
  </USSD_command>
  <USSD_command>
    <Name>Баланс Билайн</Name>
    <Command>*102#</Command>
  </USSD_command>
  <USSD_command>
    <Name>Баланс Tele2</Name>
    <Command>*105#</Command>
  </USSD_command>
  <USSD_command>
    <Name>Мой тел. МТС</Name>
    <Command>*111*0887#</Command>
  </USSD_command>
  <USSD_command>
    <Name>100Мб МТС</Name>
    <Command>*111*05*1#</Command>
  </USSD_command>
  <USSD_command>
    <Name>1Гб МТС</Name>
    <Command>*467#</Command>
  </USSD_command>
  <USSD_command>
    <Name>2Гб МТС</Name>
    <Command>*168#</Command>
  </USSD_command>
  <USSD_command>
    <Name>5Гб МТС</Name>
    <Command>*169#</Command>
  </USSD_command>
  <USSD_command>
    <Name>20Гб МТС</Name>
    <Command>*469#</Command>
  </USSD_command>
</config>`;

/*** Работа с USSD ***/
function listUSSD() {
    let xmlContent = fileExists(USSD_XML) ? readFile(USSD_XML) : DEFAULT_USSD_FILE;
    if (!xmlContent) {
        print("text[#ee5555]:Ошибка");
        return;
    }
    formatUSSDPage(xmlContent);
}

function formatUSSDPage(xmlContent) {
    const parsed = fromXML(xmlContent);
    let commands = parsed?.config?.USSD_command;
    if (!commands) {
        print("text[#ee5555]:Ошибка при получении данных");
        return;
    }
    if (!Array.isArray(commands)) commands = [commands];
    commands.forEach(command => {
        print(`text[#00cccc]:${command.Name.toUpperCase()}`);
        print(`item:${command.Command}:USSD_SEND ${command.Command}`);
    });
}

function releaseUSSD() {
    const sendCommand = `${SMS_WEBHOOK_CLIENT} ussd release 1 0`;
    execCommand(sendCommand);
}

function getUSSD(tryCount) {
    const sendCommand = `${SMS_WEBHOOK_CLIENT} ussd get 1 0`;
    
    const output = execCommand(sendCommand);
    if (output === false) {
        print("text[#ee5555]:Ошибка");
        return;
    }

    const parsed = fromXML(output);
    if (parsed.error) {
        if (parseInt(tryCount, 10) > 10) {
            print("text:Все еще жду :(");
            print("text:Попробуйте отключить режим только для 4G");
        } else {
            print("text[#00cccc]:ОТПРАВКА USSD");
            print("text[#cccccc]:Ожедание ответа");
        }
        print(`text:${".".repeat(parseInt(tryCount, 10) % 10)}`);
    } else {
        parsed.response.content.split(/[\r\n]+/).forEach(line => {
            print(`text:${line}`);
            const c = line.match(/^(\d+)\./);
            if (c !== null) {
                print(`item:${c[1]}:USSD_SEND ${c[1]}`);
            }
        });
    }
}

function sendUSSD(command) {
    const sendCommand = `${SMS_WEBHOOK_CLIENT} ussd send 2 "<request><content>${command}</content></request>"`;

    const output = execCommand(sendCommand);
    if (output !== false && output.includes("OK")) {
        print("text[#00cccc]:ОТПРАВКА USSD");
        print("text[#cccccc]:Ожедание ответа");
    } else {
        print("text[#ee5555]:Ошибка");
    }
}


/*** Работа с SMS ***/
function getMessagesCount(unread = false) {
    const sendCommand = `${SMS_WEBHOOK_CLIENT} sms sms-count 1 0`;

    let output = execCommand(sendCommand);
    if (output === false) {
        print("text[#ee5555]:Ошибка");
        return;
    }

   const parsed = fromXML(output);

   return unread ? parsed?.response?.LocalUnread : parsed?.response?.LocalInbox;
}

function formatSmsDate(d) {
    const today = new Date().toISOString().slice(0, 10).trim();
    const yesterday = new Date(new Date().getTime() - (24 * 60 * 60 * 1000)).toISOString().slice(0, 10).trim();
    const date = d.slice(0, 10).trim();
    const time = d.slice(10).trim();
    print(`yesterday: ${yesterday} ,day: ${today}, date: ${date}`);
    if (date === today) {
        return `Сегодня в ${time}`;
    } else if (date === yesterday) {
        return `Вчера в ${time}`;
    }
    return d;
}

function formatSmsPage(page, content, prefer_unread) {
    const result = fromXML(content);

    if (!result.response.Messages || result.response.Count === "0") {
        print("text:Это было последнее СМС");
        return;
    }

    const message = result.response.Messages.Message;

    // Проверка на наличие непрочитанных сообщений
    if (prefer_unread === 1 && message.Smstat === "1") {
        print("text:Больше нет непрочитанных СМС");
        return;
    }

    // Установка статуса прочитанного для сообщения
    const command = `${SMS_WEBHOOK_CLIENT} sms set-read 2 "<request><Index>${message.Index}</Index></request>"`;
    execCommand(command);

    print(`text[#00eeee]:${message.Phone}`);
    print(`text[#aaaaaa]:${formatSmsDate(message.Date)}`);
    print(`text:${message.Content.replace(/[\r\n]+/g, "\ntext:")}`);

    // Управление пагинацией и удалением сообщений
    print(`item:<Следующее>:SMS_${prefer_unread ? "UNREAD" : "ALL"}_READ ${prefer_unread ? page : page + 1}`);
    print(`item:<Удалить>:SMS_DELETE ${message.Index} ${page} ${prefer_unread}`);
}

function formatSms(page, preferUnread) {
    // Формирование XML-запроса без явного удаления переносов строк, если это допустимо API
    const requestXML = `<request><PageIndex>${page}</PageIndex><ReadCount>1</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>${preferUnread}</UnreadPreferred></request>`;

    // Вызов команды
    const command = `${SMS_WEBHOOK_CLIENT} sms sms-list 2 "${requestXML}"`;
    const output = execCommand(command); // Предполагаемая структура возвращаемого значения

    // Проверка на наличие ошибки и вызов formatSmsPage в случае успеха
    if (output === false) {
        print("text[#ee5555]:Ошибка");
    } else {
        formatSmsPage(parseInt(page, 10), output, preferUnread);
    }
}

function deleteSms(id, page, unread) {
    const command = `${SMS_WEBHOOK_CLIENT} sms delete-sms 2 "<request><Index>${id}</Index></request>"`;
    execCommand(command);
    formatSms(page, unread);
}


/*** Main ***/
function main(args) {
    if (args.length < 2) {
        const unreadCount = getMessagesCount(true);
        const totalCount = getMessagesCount(false);
        print(`text[#00cccc]:СМС`);
        print(`item:Новые (${unreadCount}):SMS_UNREAD_READ 1`);
        print(`item:Все (${totalCount}):SMS_ALL_READ 1`);
        print(`text[#00cccc]:USSD`);
        print(`item:Список команд:USSD_LIST`);
        return;
    }

    const command = args[1];
    switch (command) {
        case 'USSD_LIST':
            listUSSD();
            break;
        case 'USSD_RELEASE':
            releaseUSSD();
            break;
        case 'USSD_SEND':
            sendUSSD(args[2]);
            break;
        case 'USSD_GET':
            getUSSD(args[2]);
            break;
        case "SMS_ALL_READ":
            formatSms(args[2], 0);
            break;
        case "SMS_UNREAD_READ":
            formatSms(args[2], 1);
            break;
        case "SMS_DELETE":
            deleteSms(args[2], args[3], args[4]);
            break;
        default:
            print(`text:Неизвестная команда ${command}`);
            break;
    }
}

main(scriptArgs);