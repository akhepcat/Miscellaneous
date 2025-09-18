#!/bin/bash
# (c) 2021 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/pipewire-virtual-mapper.sh
# 
#
# Create a virtaul speaker, and sends audio streams out via it.
# Create a virtual microphone, and feeds all mics from it.
#
# based on ideas from: https://unix.stackexchange.com/questions/576785/redirecting-pulseaudio-sink-to-a-virtual-source
#

declare -A vchans

# We may have to reset everything, so if you do, run:
#    systemctl --user restart pipewire.service

pactl info >/dev/null 2>&1
res=$?
if [ ${res:-1} -ne 0 ]
then
	echo "pulseaudio support required for pipewire mapping"
	exit 1
fi

# cleanup and make sure no mappings exist
pactl unload-module module-null-sink

### VIRTUAL SPEAKER

### if pipewire is >= 0.3.67,  we can use the  "module-combine-stream" to do this instead,
### and it'll handle things better.
### https://docs.pipewire.org/page_module_combine_stream.html

USENULL=1

PVER=$(pipewire --version | tail -1 | sed 's/^[a-z ]\+//gi;' | perl -lpe '$_=sprintf("%d%03d%03d", split(/\./))' )
if [ ${PVER:-0} -gt 3067 ]
then
	USENULL=0
fi

# Test if we need to load the virtual speaker chanel (for multiple runs)
pactl get-sink-volume All_Speakers >/dev/null 2>&1
res=$?
if [ ${res:-1} -ne 0 ]
then

#	if [ -n "$(command -v pw-loopback)" ]
#	then
#		pw-loopback -n All_Speakers  -m '[FL, FR]' --capture-props='media.class=Audio/Sink' --playback-props='media.class=Audio/Source'

	if [ -n "$(command -v pw-cli)" ]
	then
		pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=All_Speakers media.class=Audio/Sink object.linger=true audio.position=[FL FR] audio.sample_rate=44100 }'
	else

		# First define the virtual speaker channel
		if [ ${USENULL:-1} -eq 1 ]
		then
			pactl load-module module-null-sink media.class=Audio/Sink sink_name=All_Speakers channel_map=front-left,front-right
		else
			pactl load-module module-combine-stream node.name=All_Speakers node.description="All Speakers combined" combine.mode=sink
		fi
	fi
fi

# Map all the stereo outputs to the virtual speaker
for CHAN in FL FR
do
	for LINK in $(pw-link -i | grep -i "playback_${CHAN}" | grep -ivE "speakers|silence|midi")
	do
		pw-link All_Speakers:monitor_${CHAN} ${LINK}
	done
done

# Likewise, map all the mono outputs to the virtual speaker
for LINK in $(pw-link -i | grep -i "playback_MONO" | grep -ivE "speakers|silence|midi")
do
	pw-link All_Speakers:monitor_FL ${LINK}
	pw-link All_Speakers:monitor_FR ${LINK}
done

# Set All_Speakers to be the default output
pactl set-default-sink  All_Speakers

### VIRTUAL MICROPHONE

# Test if we need to load the vMic-silence module (for multiple runs)
pactl get-sink-mute vMic-silence >/dev/null 2>&1
res=$?
if [ ${res:-1} -ne 0 ]
then
#	if [ -n "$(command -v pw-loopback)" ]
#	then
#		pw-loopback -n vMic-silence -m '[FL, FR]' --capture-props='media.class=Audio/Sink' --playback-props='media.class=Audio/Source'

	if [ -n "$(command -v pw-cli)" ]
	then

		pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=vMic-silence media.class=Audio/Sink object.linger=true audio.position=[FL FR] audio.sample_rate=44100 }'
	else
		# create a virtual sink to feed audio into
		pactl load-module module-null-sink  \
			sink_name=vMic-silence sink_properties=device.description=vMic-silent-sink \
			object.linger=1 media.class=Audio/Sink channel_map=front-left,front-right
	fi
fi

# Test if we need to load the vMicNoEcho module (for multiple runs)
pactl get-source-mute vMicNoEcho >/dev/null 2>&1
res=$?
if [ ${res:-1} -ne 0 ]
then
	if [ 1 -eq 1 ]
	then

		pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=vMicNoEcho media.class=Audio/Source/Virtual object.linger=true audio.position=[FL FR] audio.sample_rate=44100 }'
	else
		# create a virtual source to provide audio input from
		if [ ${USENULL:-1} -eq 1 ]
		then
			pactl load-module module-null-sink \
				sink_name=vMicNoEcho sink_properties=device.description=vMicNoEcho \
				object.linger=1 media.class=Audio/Source/Virtual channel_map=front-left,front-right
		else
			pactl load-module module-combine-stream node.name=vMicNoEcho node.description="vMicNoEcho" \
				object.linger=1 media.class=Audio/Source/Virtual combine.mode=sink
		fi
	fi
fi

# sleep while the module finishes initializing in the background
lu=$(pw-link -i | grep vMicNoEcho | wc -l)
while [ ${lu:-0} -ne 2 ]
do
	lu=$(pw-link -i | grep vMicNoEcho | wc -l)
	sleep 1
done

# Link the virtual mic input to the virtual source monitor
pw-link vMic-silence:monitor_FL vMicNoEcho:input_FL
pw-link vMic-silence:monitor_FR vMicNoEcho:input_FR

# sometimes the endpoints are L/R, sometimes they're 1/2, so we need to figure that out
CHANS=$(pw-link -i | grep vMicNoEcho | sed 's/.*_//g; ')
if [ "${CHANS}" = "${CHANS//[0-9]/}" ]
then
	vchans["FL"]="FL"
	vchans["FR"]="FR"
else
	vchans["FL"]="1"
	vchans["FR"]="2"
fi

# Set the default microphone to the virtual
pactl set-default-source vMicNoEcho

# link all physical stereo microphones to the virtual sink input
for CHAN in FL FR
do
	for LINK in $(pw-link -o | grep -i "capture_${CHAN}" | grep -ivE "speakers|silence|midi|vMicNoEcho")
	do
		pw-link ${LINK} vMic-silence:playback_${vchans[$CHAN]}
	done
done

# link all physical mono mics to the virtual sink input
for LINK in $(pw-link -o | grep -i "capture_MONO" | grep -ivE "speakers|silence|midi|vMicNoEcho")
do
	pw-link ${LINK} vMic-silence:playback_${vchans[FL]}
	pw-link ${LINK} vMic-silence:playback_${vchans[FR]}
done

#  Okay, we're done.

echo "Default speaker: All_Speakers"
echo "Default microphone: vMicNoEcho Audio/Source/Virtual"
