#!/bin/bash
# (c) 2024 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/Raspi-Firstboot.sh
# 
#   This is just some things to do after first boot
#   YMMV
#
declare -a ALLCONF

## First, some local defines

if [ -z "$(grep -i raspberry /proc/cpuinfo)" ]
then
	echo "This must be run on a Raspberry Pi"
	exit 1
fi


SSID=""
WIFIPW=""

# add config.txt options here, as strings in an array; they will not be added if already existing
# but otherwise will be added after the final "[all]"  section
### Some examples:
# dtoverlay=rpi-display,speed=16000000,rotate=90
# dtoverlay=i2c-rtc,ds1307,addr=0x68
# dtoverlay=i2c-sensor,bmp180=0x77
## default for gpio-fan is to GPIO18, pin12; change it here:
# dtoverlay=gpio-fan,temp=46000,gpiopin=23
ALLCONF=("gpu_mem=16" "dtparam=i2c_arm")

# Overclocking: base overclocking config, just uncomment the next line
# ALLCONF+=("arm_freq=800" "core_freq=250" "sdram_freq=400" "over_voltage=0" )

### list off some of those basic github repos you might want.  Use the full URI if you want something other than https://github.com
GITREPOS=( "akhepcat/Miscellaneous" "akhepcat/System-Monitor" "akhepcat/profile-repo" "akhepcat/arm-misc" "akhepcat/WhatsMyIP" "kstr0k/migrate-apt-keys" )

INFLUXURL=''	# if you're gonna use the System-Monitor repo, and you want to write to influxdb by default, but the post-api url here

###########################################

### Initial updates

apt-get update
apt-get -y install joe git build-essential gawk aptitude libdate-manip-perl i2c-tools


### install those repos we want
cd /usr/local/src
if [ -n "${GITREPOS[*]}" ]
then
	for i in ${!GITREPOS[@]}
	do
		host="https://github.com/"
		repo="${GITREPOS[i]}"
		if [ -n "${repo}" -a -z "${repo##*://*}" ]
		then
			host=""
		fi
		if [ ! -d "${repo##*/}" ]
		then
			git clone ${host}${repo}
		fi
	done
fi

### resolve the:
## W: http://raspbian.raspberrypi.com/raspbian/dists/bookworm/InRelease: 
##      Key is stored in legacy trusted.gpg keyring (/etc/apt/trusted.gpg), see the DEPRECATION section in apt-key(8) for details.
if [ -d "migrate-apt-keys" ]
then
	# only do this once per install
	/usr/local/src/migrate-apt-keys/migrate-apt-keys
fi

aptitude -y dist-upgrade
apt-get autoclean
apt-get autoremove

### install our default profile
if [ -z "$(ls -alF ~/.profile | grep repo)" ]
then
	cd /usr/local/src/profile-repo
	./install_profile
	rm -f ~/.*_local
fi

### Basic sysmon install

if [ ! -r /etc/default/sysmon.conf ]
then
	cd ~
	mkdir -p bin/sysmon
	cd ~/bin/sysmon
	ln -sf /usr/local/src/System-Monitor/* .
	rm sysmon.conf
	cp /usr/local/src/System-Monitor/sysmon.conf /etc/default
	rm -f README.md dnsResponseTimePing.pl dexcom.sh environmental.txt fping.sh influxdb-help.txt ookla.pl sda1.sh eth0.sh \ 
	      page_load_time.pl resolvers.sh response.sh sitestats.sh smtp-response.py speedtest.sh webpage.sh uptime.sh \
		webspeed.sh wg_status.sh wgstats.pl bmp180-i2c.py bmp180-iio.sh bmp180.sh scd4x-i2c.py scd4x.sh

	sed -i "s|^DONTRRD=.*|DONTRRD=1|; s|^INFLUXURL=.*$|INFLUXURL=\"${INFLUXURL}\"|;" /etc/default/sysmon.conf
	sed -i "s|^SERVERNAME=.*|SERVERNAME=\"$(hostname)\"|" /etc/default/sysmon.conf

	PROGS=$(/bin/ls *.sh)
	CMD="sed -i '"'s/^PROGS=.*/PROGS="'${PROGS}'"/'"'"
	eval $CMD /etc/default/sysmon.conf

	cat >/etc/cron.d/sysmon <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * *   root    test -x /root/bin/sysmon/do-updates && /root/bin/sysmon/do-updates auto
EOF

### end of sysmon install
fi

###  permissions fixups

# who is the local user who can sudo?
luser=$(grep sudo /etc/group | cut -f 4 -d:)
cd /usr/local
[[ -d src ]] && chown -R ${luser} src
lhome=$(getent passwd ${luser} | cut -f6 -d:)
test -z "$(ls -alF ${lhome}/.profile | grep repo)" && su -l ${luser} -c "cd /usr/local/src/profile-repo && echo ./install_profile && echo rm -f ~/.*_local"

if [ -r /boot/firmware/cmdline.txt ]
then
	FWD="/boot/firmware"	# both cmdline.txt and config.txt are in /boot/firmware
elif [ -r /boot/cmdline.txt ]
then
	FWD="/boot"	# both cmdline.txt and config.txt are in /boot
else
	FWD=""
fi
if [ -n "${FWD}" ]
then
	# Make sure we can hotplug the HDMI and get output, even without a keyboard to unblank the screen, by disabling consoleblank
	[[ -z "$(grep vc4.force_hotplug ${FWD}/cmdline.txt)" ]] && sed -i 's/$/ vc4.force_hotplug=1/;' ${FWD}/cmdline.txt
	if [ -z "$(grep 'consoleblank' ${FWD}/cmdline.txt)" ]
	then
		sed -i 's/$/ consoleblank=0/;' ${FWD}/cmdline.txt
	else
		sed -i 's/\(consoleblank\)\(=[0-9]\+\)/\1=0/;' ${FWD}/cmdline.txt
	fi

	# if there's no "[all]" in config.txt, add one to the end
	if [ -z "$(grep -Fi '[all]' ${FWD}/config.txt)" ]
	then
		echo -e "\n[all]\n" >> ${FWD}/config.txt
	fi

	## common to ALL pi hardware
	# print from the beginning, up to and including the keyword "[all]"
        for i in ${!ALLCONF[@]}
        do
                echo "i is $i, ctext=${ALLCONF[i]}"
                line=$(grep -F "${ALLCONF[i]}" ${FWD}/config.txt)
                if [ -n "${line}" ]
                then
                        unset -v "ALLCONF[i]"
                fi
        done
        if [ -n "${ALLCONF[*]}" ]
        then
                sed -n '1,\|\[all\]|p' ${FWD}/config.txt > ${FWD}/config.txt.new
                for i in ${!ALLCONF[@]}
                do
                        echo "${ALLCONF[i]}"  >> ${FWD}/config.txt.new
                done
                # finish printing from after that keyword "[all]" to EOF
                sed -n '\|\[all\]|,$p' ${FWD}/config.txt  | sed '1d'  >> ${FWD}/config.txt.new

                ## end all common config.txt
        fi

else
	echo "can't find cmdline.txt in either /boot or /boot/firmware"
fi

if [ -d /etc/NetworkManager/system-connections -a -n "${SSID}" -a -z "$(ls /etc/NetworkManager/system-connections/${SSID}*)" ]
then
	# for generic wireless access when not plugged into ethernet
	nmcli dev wifi connect "${SSID}" password "${WIFIPW}"
fi

echo "Completed!  You'll want to reboot to activate all the changes"
