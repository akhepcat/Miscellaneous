#!/bin/bash
# (c) 2021 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/v6-v4.sh
# 
# simple, dumb wrapper to parse active IPv4 addresses and encode them into a 4-in-6 address
#

for IFACE in $(ip link show  | grep 'state UP' | cut -f 2 -d:)
do
        ipv4="""$( ip -4 addr show dev ${IFACE} scope global | grep "inet .*${IFACE}" | sed 's/\/.*//g; s/.*inet //g' )"""
        ipv6="${ipv4//\./ }"
        ipv6="$( printf '2002:%02x%02x:%02x%02x::1' $ipv6)"

        echo "${IFACE} ${ipv4} == ${ipv6}"
done

