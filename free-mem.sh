#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/free-mem.sh
# 
# Dumb cron-able script to drop caches every night and free up some memory.
# Is it *really* needed?  probably not.  Until it is.
# 
# we use MemTotal to figure out a baseline minimum, and then check against MemAvailable
# to see which minimum is probably "more right"

kTotl=$(grep MemTotal /proc/meminfo | awk '{print $2}')
kInst=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
kFree=$(grep MemFree /proc/meminfo | awk '{print $2}')

kMin=$(( ${kTotl:-0} / 4 ))
if [ ${kMin:-0} -gt 1024 -a ${kMin:-0} -lt 65536 ]
then
        kMin=65536
fi

kLim=$(( kInst / 4 ))

# make adjustments for lo-mem (2GB or less) devices
if [ ${kInst:-0} -lt 2097152 -a ${kLim:-0} -gt ${kMin} ]
then
        kLim=${kMin}
fi

if [ ${kFree:-0} -lt ${kLim} ]
then
        echo "3" > /proc/sys/vm/drop_caches
fi
