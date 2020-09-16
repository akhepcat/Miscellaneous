#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/4to6proxy.sh
# 
PROG="${0##*/}"

trap cleanup SIGINT SIGTERM SIGKILL SIGQUIT SIGABRT SIGSTOP SIGSEGV

cleanup() {
	echo -e "\n\n"
	test -e "${PIPE}" && rm -f "${PIPE}"
	exit 0
}


PORT=${1}
PORT=${PORT//[^0-9]/}

if [ -z "${PORT}" ]
then
	echo "${PROG} - proxy localhost IPv4 port to localhost IPv6 port"
	echo "usage:  ${PROG} [port]"
	exit 1
fi

SOCAT=$(which socat)
NETCAT=$(which nc)
test -z "${NETCAT}" && NETCAT=$(which netcat)

if [ -n "$(which socat)" ]
then
	${SOCAT} TCP4-LISTEN:${PORT},fork,su=nobody,bind=127.0.0.1,reuseaddr TCP6:[::1]:${PORT}

elif [ -n "${NETCAT}" ]
then
	PIPE=$(mktemp --dry-run)
	if [ ! -e "$PIPE" ];
	then
		mknod "$PIPE" p
		${NETCAT} -l -4 127.0.0.1 ${PORT} 0<"$PIPE" | ${NETCAT} -6 ::1 ${PORT} 1>"$PIPE"
	fi
else
	echo "Can't find socat or netcat(nc)  binary, can't proxy IPv4:${PORT}::IPv6:${PORT}"
fi
