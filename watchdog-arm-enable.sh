#!/bin/bash

if [ ! \( \( "${USER}" = "root" \) -o \( -n "${EUID}" -a ${EUID} = 0 \) \) ]
then
        echo "root privs required. re-run with sudo."
        exit 1
fi

if [ -z "$(grep -i raspberry /proc/cpuinfo)" ]
then
	echo "not running on a RaspberryPI - aborting"
	exit 1
fi

if [ -z "$(egrep -i 'watchdog.*=.*on' /boot/config.txt /boot/firmware/config.txt 2>/dev/null | grep -v '^#')" ]
then
	if [ -r /boot/firmware/config.txt ]
	then
		echo 'dtparam=watchdog=on' >> /boot/firmware/config.txt

	elif [ -r /boot/config.txt ]
	then
		echo 'dtparam=watchdog=on' >> /boot/config.txt
	else
		echo "add  'dtparam=watchdog=on' to your config file and reboot"
	fi
fi

if [ ! -e /etc/watchdog.conf ]
then
	apt-get update
	apt-get install watchdog

	systemctl enable watchdog
fi
systemctl stop watchdog

MyV4Int=$(awk 'BEGIN { IGNORECASE=1 } /^[a-z0-9:.-]+[ \t]+00000000/ { print $1 }' /proc/net/route 2>/dev/null | head -1)

cat >> /etc/watchdog.conf <<EOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
max-load-1 = 24

interface = ${MyV4Int}
EOF

systemctl start watchdog
systemctl status watchdog
