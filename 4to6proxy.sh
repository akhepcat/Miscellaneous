#!/bin/bash
PROG="${0##*/}"

PORT=${1}

if [ -z "${PORT}" ]
then
	echo "${PROG} - proxy localhost IPv4 port to localhost IPv6 port"
	echo "usage:  ${PROG} [port]"
	exit 1
fi

socat TCP4-LISTEN:${PORT},fork,su=nobody,bind=127.0.0.1,reuseaddr TCP6:[::1]:${PORT}
