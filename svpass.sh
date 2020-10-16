#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/svpass.sh
# 
NOW=$(date "+%s")

lat=41.6172		# Lattitude, 4-digit precision;  we round to 2-digits for display
long=-70.4369		# Logitude, 4-digit precision; we round to 2-digits for display
elev=212		# Elevation above sea-level, in meters
loc="FN41so"		# Grid location
city="Cotuit, MA"	# Where are you

count=40		# max number of rows (40 gives at least a week)
SV="ISS"		# The space vehicle to track.

cache="${HOME}/.cache/svpass.dat"	# where the cache file lives

URL="https://www.amsat.org/track/"	# the location to interface

## head -16 svpass.sh | tail -14 > ${HOME}/.config/.svpass
##########################################################################
[[ -r ${HOME}/.config/svpass.cfg ]] && . ${HOME}/.config/svpass.cfg   # overload the static config

[[ -r ${cache} ]] && CLAST=$(stat  --format="%Y" ${cache}) || CLAST=0

rlat=$(printf '%.*f\n' 2 $lat)
rlong=$(printf '%.*f\n' 2 $long)

cat <<HTML
<!DOCTYPE html>
<html>

<head>

<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta http-equiv="Content-Style-Type" content="text/css" />
<meta http-equiv="Refresh" content="300" />
<meta http-equiv="Pragma" content="no-cache" />
<meta http-equiv="Cache-Control" content="no-cache" />
<title> ${ISS} Passes for ${city} </title>

<style>
body {
  background-color: #e6e6ff;
}

table {
	border: 1px solid black;
	text-align: center;
	padding: 10px;
	width: 75%;
	margin-left:auto;
	margin-right:auto;
}
th {
	border: 1px solid black;
	text-align: center;
	padding: 10px;
	border-bottom: 1px solid;
}
td {
	border: 1px solid black;
	text-align: center;
	padding: 10px;
}

td:hover { background-color: #ffff33; }

caption {
	caption-side: top;
}

div.clockbox {
	align: center;
	font-size: x-large;
	text-align: center;
	padding: 10px;
	width: 75%;
	margin-left:auto;
	margin-right:auto;
}

</style>
</head>

<body>

<h2>${SV} overhead passes for ${city} (approx: ${rlat} x ${rlong} @ ${elev}m elevation)</h2>
<p>
The data in the table below is scraped from <a href="${URL}">${URL}</a> once every 7 days, and cached locally.<br />
It is converted from UTC time to local ${city} time, and provided here as a convenience.
<br />
No guarantee of the accuracy is given.   Verification against alternate sources, such as <a href="https://www.n2yo.com/passes/?s=25544">N2YO.com</a>
is highly advisable.
</p>
<p>The crew's usual waking period is 0730 - 1930 UTC, so this script will try to highlight those good passes that occur
when the crew is awake.
</p>
<p>The script updates the page every 5 minutes to provide a visual indicator of fresh vs stale passes. <br />
<br />
Last update at $(date)</p>
HTML

# Amsat's east/west logic is backward!
if [ ${long//./} -lt 0 ]
then
	longdir="longdir="
	long=${long//-/}
else
	longdir="longdir=-"
fi
if [ ${lat//./} -lt 0 ]
then
	latdir="longdir=-"
	lat=${lat//-/}
else
	latdir="latdir="
fi

[[ -r "${cache}" ]] && caption="local cache last update: $(date -r ${cache} )"

if [ $(( ${CLAST:-0} + (86400 * 7) )) -lt ${NOW} ]
then
	caption="Refreshing now"	
	curl \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--referer "${URL}" \
		-X POST \
		-d "lang=en&satellite=${SV}&lat=${lat}&lng=${long}&${latdir}&${longdir}&ele=${elev}&loc=${loc}&count=${count}&submit=true&doPredict=%20Predict%20&saveme=0" \
		--output "${cache}" \
		"${URL}"
fi


cat <<HTML
<div style="align: center;">

<table>
  <caption>Legend</caption>
  <tr><td style="background-color: #ffff33;width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>pass in progress</td></tr>
  <tr><td style="background-color: #99ff99;width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>good pass</td></tr>
  <tr><td style="background-color: #fff2e6;width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>marginal pass</td></tr>
  <tr><td style="background-color: #ffcccc;width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>bad pass</td></tr>
  <tr><td style="background-color: #656565;width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td>stale</td></tr>
  <tr><td colspan="2" style="background-color: #222222;"></td></tr>
  <tr><td style="width: 75%;margin-left:auto;margin-right:auto;">[any background color]</td><td style="font-weight: bolder; color: black;">Crew Awake</td></tr>
  <tr><td style="width: 75%;margin-left:auto;margin-right:auto;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td style="font-weight: lighter; color: purple;">Crew Asleep</td></tr>
</table>

<p>&nbsp;</p>
<hr style="width: 50%; align: center;" />
<div class="clockbox" id="clockbox"></div>
<p>&nbsp;</p>

<table>
<caption>${caption}</caption>
<tr> <th>Date & Time at AoS</th> <th>Duration</th> <th>AoS Azimuth</th> <th>AoS Elevation</th> <th>Max Azimuth</th> <th>Min Azimuth</th> <th>Time & Date at LoS</th> </tr>
HTML

for line in $(sed 's|</tr><tr|</tr>\n<tr|g;' "${cache}" | grep -E 'table|<tr.*td' | html2text | grep -v '______' | sed 's/^\([[:space:]]\+\)\?|//g; s/|$//g;' )
do
	# 14_Oct_20|22:50:34|00:09:32|251|16|191|129|23:00:06
	
	line=${line//_/ }

	DATE=$(echo $line | cut -f1 -d\|)  
	AOST=$(echo $line | cut -f2 -d\|)
	DURT=$(echo $line | cut -f3 -d\|)
	AZIM=$(echo $line | cut -f4 -d\|)
	ELEV=$(echo $line | cut -f5 -d\|)
	MAXAZ=$(echo $line | cut -f6 -d\|)
	LOSAZ=$(echo $line | cut -f7 -d\|)
	LAST=$(echo $line | cut -f8 -d\|)

	# convert to local time, 'set  TZ' env variable to force a different zone
	NEWD=$(date --date="${DATE} ${AOST} UTC" '+%Y-%m-%d %H:%M:%S')
	WIND=$(date --date="${DATE} ${AOST} UTC" '+%s')
	THEN=$(date --date="${DATE} ${LAST} UTC" '+%s')
	LOST=$(date --date="${DATE} ${LAST} UTC" '+%Y-%m-%d %H:%M:%S')

	HB=$(date --date="${DATE} 07:30 UTC" '+%s')
	HE=$(date --date="${DATE} 19:30 UTC" '+%s')

	font="font-weight: lighter; color: purple;"

	if [ $((THEN + 43200 )) -lt $NOW ]
	then
		# It's older than 12H, so we'll skip it.
		bg=""
	elif [ $NOW -le $THEN ]
	then
		if [ $NOW -ge $WIND -a $((NOW - 500)) -lt $THEN ]
		then
			bg="#ffff33"

		elif [ ${ELEV:-0} -gt 13 ]
		then
		# highlight the good passes
			bg="#99ff99"

			if [ $WIND -gt $HB -a $THEN -le $HE ]
			then
				font="font-weight: bolder; color: black;"
			fi
		elif [ ${ELEV:-0} -gt 7 ]
		then
			#marginal
			bg="#fff2e6"
			if [ $WIND -gt $HB -a $THEN -le $HE ]
			then
				font="font-weight: bold; color: black;"
			fi
		else
			#bad
			bg="#ffcccc"
		fi


		COUNT=$((COUNT +1))
	else
		bg="#656565"
	fi

	[[ -n "${bg}" ]] && echo -e "<tr style='background-color: ${bg}; ${font}'> <td>${NEWD}</td> <td>${DURT}</td> <td>${AZIM}</td> <td>${ELEV}</td> <td>${MAXAZ}</td> <td>${LOSAZ}</td> <td>${LOST}</td> </tr>\n"

done

if [ ${COUNT:-0} -lt 5 ]
then
	rm -f ${cache}
	EXTRA="<p>Next run will refresh cache.</p>"
fi

cat <<HTML
</table>
</div>

<p>${COUNT} valid passes (of $count) remaining in cache</p>
${EXTRA}

<!-- for the clock, you can use: https://www.ricocheting.com/code/javascript/html-generator/date-time-clock -->
<!-- I don't embed it due to CSTS security restrictions on inline javascript -->
<script type="text/javascript" src="lib/jsclock.js">
</script>

<hr />
(c) 2020 KL5BN, Leif Sawyer<br />
<a href="https://github.com/akhepcat/Miscellaneous/blob/master/svpass.sh">Use the source, Luke!</a>
</body>
</html>
HTML

## EOF
