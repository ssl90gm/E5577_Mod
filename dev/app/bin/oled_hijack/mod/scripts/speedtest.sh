#!/bin/sh

HOME=/root
LD_LIBRARY_PATH=/app/lib:/system/lib:/system/lib/glibc
PATH=/bin:/sbin:/app/bin:/system/sbin:/system/bin:/system/xbin

/app/bin/speedtest --accept-license -p -f json /dev/null > /tmp/speedtest