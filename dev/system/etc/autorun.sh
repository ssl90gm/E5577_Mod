#!/system/bin/busybox sh

mkdir bin
ln -s /system/bin/sh /bin/sh
ln -s /system/bin/busybox /bin/ash
ln -s /system/xbin/atc.sh /sbin/atc
mkdir /var /opt /tmp /online/opt
# For Entware
mount --bind /online/opt /opt

# For TUN/TAP
mkdir /dev/net
mknod /dev/net/tun c 10 200

# /tmp (speedtest etc.)
mkdir /tmp
mount -t tmpfs tmpfs /tmp


busybox echo 0 > /proc/sys/net/netfilter/nf_conntrack_checksum

# NV restore flag, load patches only when normal boot.
if [[ "$(cat /proc/dload_nark)" == "nv_restore_start" ]];
then
    /system/sbin/NwInquire &

    /etc/huawei_process_start
    exit 0
fi

/etc/fix_ttl.sh 0
/etc/huawei_process_start

insmod /system/xbin/kpatch.ko addr=g_bAtDataLocked data=0,0,0,0 2> /dev/null

insmod /system/xbin/kpatch.ko addr=nv_readEx off=0x154 data=0xBF,0xFF,0xFF,0xEA 2> /dev/null
insmod /system/xbin/kpatch.ko addr=nv_writeEx off=0x4C data=0x00,0x00,0xA0,0xE1 2> /dev/null

# Load kernel modules
for kofile in /system/bin/kmod/*.ko;
do
    insmod "$kofile"
done

# Set time closer to a real time for time-sensitive software.
# Needed for everything TLS/HTTPS-related, like DNS over TLS stubby,
# to work before the time is synced over the internet.
date -u -s '2024-02-18 00:00:00'

# Load custom sysctl settings
busybox sysctl -p /system/etc/sysctl.conf

# Remove /online/mobilelog/mlogcfg.cfg if /app/config/mlog/mlogcfg.cfg does NOT exist
# Disables mobile logger and saves flash rewrite cycles
[ ! -f /app/config/mlog/mlogcfg.cfg ] && rm /online/mobilelog/mlogcfg.cfg

[ ! -f /data/userdata/passwd ] && cp /system/usr/default_files/passwd_def /data/userdata/passwd
[ ! -f /data/userdata/telnet_disable ] && telnetd -l login -b 0.0.0.0

if [ -f /app/bin/oled_hijack/autorun.sh ];
then
    /app/bin/oled_hijack/autorun.sh
    # Start adb if oled_hijack is present by default.
    # Adb access would be blocked by default via remote_access oled_hijack script.
    [ ! -f /data/userdata/adb_disable ] && adb
else
    # Non-OLED device. Uncomment to enable adb by default.
    # Adb could still be launched via telnet 'adb' command.
    [ ! -f /data/userdata/adb_disable ] && adb
    true
fi

# Entware autorun
[ -f /data/userdata/entware_autorun ] && /opt/etc/init.d/rc.unslung start

# fix_ttl.sh 2, dns_over_tls.sh and anticenshorship.sh are called
# from /system/bin/iptables-fixttl-wrapper.sh by /app/bin/npdaemon.

/app/webroot/webui_init.sh

mkdir -p /data/dropbear
/system/bin/dropbear -R

#MOD
/app/bin/oled_hijack/mod/scripts/shadowsocks.sh boot
/system/xbin/vpn_init.sh