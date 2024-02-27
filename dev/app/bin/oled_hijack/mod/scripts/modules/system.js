import * as std from 'std';

function fileExists(filePath) {
    return std.open(filePath, "r") !== null;
}

function readFile(filePath) {
    let file = std.open(filePath, "r");
    if (!file) return null;
    let content = file.readAsString();
    file.close();
    return content;
}

function writeToFile(filePath, data) {
    let file = std.open(filePath, "w");
    if (!file) return null;
    file.puts(data);
    file.close();
}

function execCommand(command) {
    let output = "";
    let pipe = std.popen(command, "r");
    if (!pipe) return false;

    while (true) {
        let line = pipe.getline();
        if (line === null) break;
        output += line + "\n";
    }

    let exitCode = pipe.close();
    if (exitCode !== 0) return false;

    return output;
}

// Экспорт функций модуля
export { fileExists, readFile, writeToFile, execCommand };
