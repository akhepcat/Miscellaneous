#!/bin/bash
# (c) 20170707 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/listeners.sh
# 
# replicates:
#       lsof -i -n -P | grep LISTEN | sort -n -k +2 -t: | grep -vE '127.0.0.1|::1' | uniq -f 7
# without multiple execs

if [ -n "$1" -a "${1}" = "-l" ]
then
	FILTER="all"
else
	FILTER="local"
fi

GAWK=$(command -v gawk)
AWK=$(command -v awk)

USE_AWK=${GAWK:-$AWK}

if [ -n "$(command -v lsof)" ]
then
    lsof -i -n -P +c15 | ${USE_AWK} -v filter=${FILTER} '
# LSOF replaces spaces in the procname with \x20, which we CAN remove, else formatting
#	$0 ~ /\\x20/ {
#		gsub("\\\\x20"," ",$0)
#	}


# Look for global listeners (ignore localhost if flagged)
	/LISTEN/ {
		if ( (filter ~ /local/) && (/127.0.0.1/ || /::1/) ) {
		   next;
		}
		myline=$0;
		if ( filter ~ /all/ ) {
		  gsub("127.0.0.1","",myline);
		  gsub("::1","",myline);
		}
		FS=":";
		split($2,portArr," ");
		port=portArr[1];
		if (!line[port]) {
               	        line[port]=myline;
               	};
	};
	
# Sort the command-lines by the listening port
	END {
		j=1;
		for ( i in line) {
			ports[j] = i;
			j++;
		};
		n = asort(ports,null,"@ind_num_asc")
		for (i = 1; i <= n; i++) {
			print line[null[i]];
		};
	};
'
# end
elif [ -n "$(command -v ss)" ]
then
	ss -nlp |  awk '/tcp|udp/ { printf "%s  %s  %45s  %15s  %s\n", $1, $2, $5, $6, $7 }' | sed 's/users:((\"\([a-zA-Z0-9_-]\+\)\",.*/\1/g;'

elif [ -n "$(command -v netstat)" ]
then
	# last resort
	netstat -a -n | grep -E '^(tcp|udp|icmp)' | grep -vE 'ESTAB|TIME'
else
	# eek!
	echo "Can't figure out how to look for open ports:"
	echo "  install one of lsof, ss, or netstat"
	exit 1
fi
