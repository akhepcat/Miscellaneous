#!/bin/bash
# (c) 2022 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/dshield-to-fail2ban.sh
# 

blocks=$(mktemp /tmp/dshield-ban.XXXXXXX)
if [ -e "${blocks}" ]
then
	curl -silent https://www.dshield.org/block.txt > ${blocks}

	cidrs=$(grep -E '^[0-9]+' ${blocks} | awk '{print $1}' | tr '\n' ' ' | sed 's| |/24 |g;')
	for jail in $(fail2ban-client status | grep 'Jail list' | sed 's/.*://; s/[[:space:]]//g; s/,/ /g;')
	do
		fail2ban-client set ${jail} banip ${cidrs} >/dev/null 2>&1
	done

	rm -f ${blocks}
else
	echo "Can't create tmpfile"
fi
