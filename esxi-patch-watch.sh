#!/bin/bash
# (c) 2021 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/esxi-patch-watch.sh
# 
# throw this in cron to get an email when patches are released.
# it's safe to run once a week, shouldn't need more often than that.

# replace as needed from https://esxi-patches.v-front.de/Subscribe-RSS.html - using the "manual" link
URL="https://esxi-patches.v-front.de/atom/ESXi-6.7.0.xml"

if [ -d "${HOME}/.cache" ]
then
	CFILE="${HOME}/.cache/esxi-updater.cache"
else
	CFILE="${HOME}/.esxi-updater.cache"
fi

if [ -r "${CFILE}" ]
then
	LDATE=$(cat "${CFILE}")
fi

CDATE=$(curl --SILENT ${URL} | sed 's|</|\n</|g; s|/>|/>\n|g;' | head | grep '<updated>')
CDATE=${CDATE//<updated>/}

if [ -n "${CDATE}" ]
then
	CDATE=$(date --date="${CDATE}" "+%s")
fi

if [ ${CDATE:-0} -gt ${LDATE:-0} ]
then
	echo $CDATE > ${CFILE}

	echo "New ESXi patches available on ${URL}"
fi
