#!/bin/bash
#
# Dumb cron-able script to drop caches every night and free up some memory.
# Is it *really* needed?  probably not.  Until it is.

kInst=$(grep MemTotal /proc/meminfo | awk '{print $2}')
kFree=$(grep MemFree /proc/meminfo | awk '{print $2}')

kLim=$(( kInst / 4 ))

if [ ${kLim:-0} -lt 65536 ]
then
        kLim=65536
fi

if [ ${kFree:-0} -lt ${kLim} ]
then
        echo "3" > /proc/sys/vm/drop_caches
fi
