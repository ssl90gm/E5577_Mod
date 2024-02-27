adb kill-server
adb connect 192.168.8.1:5555

adb push install.tgz /

adb shell "cd /"

adb shell "mount -o remount,rw /system"
adb shell "mount -o remount,rw /app"
adb shell "mount -o remount,rw /app/webroot"

adb shell "rm /system/bin/openvpn"
adb shell "rm /system/bin/qjs"

adb shell "busybox tar zxvf install.tgz"
adb shell "rm install.tgz"

adb shell "chmod 775 /app/webroot/httpd_root/cgi-bin/openvpn.cgi"
adb shell "chmod 775 /system/xbin/*"
adb shell "chmod 775 /system/etc/autorun.sh"
adb shell "chmod 775 /system/etc/huawei_process_start"
adb shell "chmod 775 /system/bin/entware"
adb shell "chmod 775 /system/bin/dropbear"
adb shell "chmod 775 /system/bin/kmod/01_tun.ko"
adb shell "chmod -R 775 /app/bin/*"


adb shell "rm -rf /online/opt"
adb push opt.tgz /online
adb shell "cd /online; busybox tar zxvf opt.tgz"
adb shell "cd /online; rm opt.tgz"


adb shell "reboot"

pause