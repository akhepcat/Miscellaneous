#!/bin/bash
# (c) 20170707 - lsawyer
# replicates:
#       lsof -i -n -P | grep LISTEN | sort -n -k +2 -t: | grep -vE '127.0.0.1|::1' | uniq -f 7
# without multiple execs

if [ -n "$1" -a "${1}" = "-l" ]
then
	FILTER="all"
else
	FILTER="local"
fi

GAWK=$(which gawk)
AWK=$(which awk)

USE_AWK=${GAWK:-$AWK}

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
