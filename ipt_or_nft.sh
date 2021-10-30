#!/bin/bash

if [ "$USER" != "root" ]
then
        echo "Must be run as root"
        exit 1
fi

if [ -n "$(which nft)" ]
then
        NFTL=$(nft -s -nnn list ruleset | wc -l)
fi

if [ -n "$(which iptables-save-legacy)" ]
then
        IPTLL=$(iptables-legacy-save | grep -vE '^[:#*]|COMMIT' | wc -l )
fi
if [ -n "$(which iptables-save)" ]
then
        IPTL=$(iptables-save | grep -vE '^[:#*]|COMMIT' | wc -l )
fi

# echo "NFT lines:         ${NFTL:-0}"
# echo "IPT lines:         ${IPTL:-0}"
# echo "IPT(legacy) lines: ${IPTLL:-0}"

if [ ${NFTL:-0} -gt ${IPTL:-0} -a ${NFTL:-0} -gt ${IPTLL:-0} ]
then
	echo "NFtables is running"
elif [ ${IPTL:-0} -gt ${NFTL:-0} -a  ${IPTL:-0} -gt ${IPTLL:-0} ]
then
	echo "IPTables is running"
elif [ ${IPTLL:-0} -gt ${IPTL:-0} -a ${IPTLL:-0} -gt ${NFTL:-0} ]
then
	echo "IPtables-Legacy is running"
else
	echo "none, or can't figure out what's running"
fi
