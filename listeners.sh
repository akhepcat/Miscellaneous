#!/bin/bash
# (c) 20170707 - lsawyer
# replicates:
#       lsof -i -n -P | grep LISTEN | sort -n -k +2 -t: | grep -vE '127.0.0.1|::1' | uniq -f 7
# without multiple execs

lsof -i -n -P | awk '
	/LISTEN/ && !( /127.0.0.1/ || /::1/ ) {
		myline=$0;
		FS=":";
		split($2,portArr," ");
		port=portArr[1];
		if (!line[port]) {
               	        line[port]=myline;
               	};
	};
	
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
