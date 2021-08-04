#!/bin/bash
#
# Simple in-dir minecraft server updater.

SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]
do
        # resolve $SOURCE until the file is no longer a symlink
        DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
PDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd -P )"
## end

UA="Mozilla/5.0 (X11; Linux x86_64)"

echo "Grabbing URL..."
URL=$(curl -A "${UA}" --silent https://www.minecraft.net/en-us/download/server/bedrock | grep -i linux/bedrock-server   | sed 's/.*href=//g;' | cut -f2 -d\")

FN=${URL##*/}
echo "File: ${FN}"

# make sure the requisite directories exist
mkdir -p "${PDIR}/updates/" "${PDIR}/CONFIG/"

if [ -r "${PDIR}/updates/${FN}" ]
then
	echo "running at current version, no update needed"
else

	if [ -n "$1" -a "$1" != "check" ]
	then
		echo "$0 - updates the minecraft server"
		echo "$0 check - only checks for updates, does not apply them"
		echo "     no other args are accepted or required"
		exit 1
	elif [ "$1" = "check" ]
	then
		echo "Update check-only complete, please manually update"
		exit 0
	fi

	echo "Fetching update: ${FN}"
	wget --referer=https://www.minecraft.net/en-us/download/server/bedrock/ -O "${PDIR}/updates/${FN}" "${URL}"


	if [ -z "$(pgrep bedrock_server)" ]
	then
		echo "backing up config files for ${server}"
		cp permissions.json valid_known_packs.json whitelist.json server.properties "${PDIR}/CONFIGS/"

		echo "unpacking update"
		unzip "${PDIR}/updates/${FN}" -x permissions.json valid_known_packs.json whitelist.json server.properties

		cp "${PDIR}/CONFIGS"/* .
		chmod +x bedrock_server
	else
		echo "Stop the existing bedrock server before updating"
		exit 1
	fi
fi
