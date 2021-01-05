#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/l2tpv3-cisco.sh
# 
# using l2tpV3 between linux and cisco is sometimes weird.
# this script is how I get the linux side up.
# This will also auto-generate the cisco-side config.
################################

TUNNEL_ID=101
REMOTE_TUNNEL_ID=${TUNNEL_ID}

SESSION_ID=101
REMOTE_SESSION_ID=${SESSION_ID}

LOCAL=10.1.1.1
REMOTE=10.100.100.1

################################
PATH=/sbin:$PATH
IPV=$(ip -V | sed 's/.*-ss//')

if [ ${IPV:-0} -lt 130716 ]
then
	echo "Please install a newer version of iproute2 ( 3.10 or (>= 2013-07-16))"
	echo "  from https://www.kernel.org/pub/linux/utils/net/iproute2/"
	exit
fi


modules() {
	for module in l2tp_core l2tp_netlink l2tp_eth l2tp_ip
	do
		modprobe $i
	done
}
	
tunnel_up() {
	ip l2tp add tunnel remote ${REMOTE} local ${LOCAL} tunnel_id $TUNNEL_ID peer_tunnel_id $REMOTE_TUNNEL_ID encap ip
	ip l2tp add session tunnel_id $TUNNEL_ID session_id $SESSION_ID peer_session_id $REMOTE_SESSION_ID l2spec_type none
	ip link set l2tpeth0 up mtu 1488
	iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1448:1536 -j TCPMSS --set-mss 1448
}

tunnel_down() {
	iptables -D FORWARD -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1448:1536 -j TCPMSS --set-mss 1448
	ip link set l2tpeth0 down
	ip l2tp del session tunnel_id $TUNNEL_ID session_id $SESSION_ID
	ip l2tp del tunnel tunnel_id $TUNNEL_ID
}

cisco_config() {
cat <<EOF
! Global config
!
    pseudowire-class Linux-L2TP
	encapsulation l2tpv3
	interworking ethernet
	protocol none
	ip local interface $REMOTE
	ip pmtu
	ip tos value 41
	ip ttl 100
!
! Interface config
!
    interface \$L2interface
	xconnect $LOCAL $REMOTE_TUNNEL_ID encapsulation l2tpv3 manual pw-class Linux-L2TP
	    l2tp id $SESSION_ID $REMOTE_SESSION_ID

EOF
}

case $1 in
	start|up) tunnel_up
	;;
	stop|down) tunnel_down
	;;
	restart|reload) stop; start
	;;
	config|cisco|cisco-config) cisco_config
	;;
	*) echo "$0  (start|up || stop|down || restart|reload || config|cisco|cisco-config)"
	;;
esac
