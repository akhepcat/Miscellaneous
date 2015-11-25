#!/bin/bash

BASE=/mnt/disk/android		# change this to your build root
PROXY=""	# If you want/need to use a web proxy

trap cleanup SIGINT SIGTERM SIGKILL SIGQUIT SIGABRT SIGSTOP SIGSEGV

###################################
NICE=""

if [ -n "${PROXY}" ]
then
	export http_proxy="${PROXY}/"
	export https_proxy="${PROXY}/"
	export ftp_proxy="${PROXY}/"
	if [ -z "${PROXY##*http*}" ]
	then
		git config --global http.proxy "${PROXY##*//}"
	elif [ -z "${PROXY##*sock*}" -o -z "${PROXY##*1080}" ]
	then
		git config --global socks.proxy "${PROXY##*//}"
	else
		echo "Unknown proxy for git, type: ${PROXY}"
	fi
else
	git config --global http.proxy ""
	git config --global socks.proxy ""	
fi

export CROSS_COMPILE=${BASE}/M/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-
export ARCH=arm

Mver=6.0.0_r1
Lver=5.1.1_r1

cleanup()
{
	# Not much to do here right now
	exit -1
}

latest_M()
{
	## latest is
	Mlatest=$( curl --silent https://android.googlesource.com/platform/manifest/+refs | sed 's/\"/\n\r/g' | grep '/android-6' | sed 's/.*android-//g' | sort -Vu | tail -1)
}

latest_L()
{
	## latest is
	Llatest=$( curl --silent https://android.googlesource.com/platform/manifest/+refs | sed 's/\"/\n\r/g' | grep '/android-5.1' | sed 's/.*android-//g' | sort -Vu | tail -1)
}

get_marshmallow()
{
	#get android M AOSP into folder called M
	test -d ${BASE}/M || mkdir -p ${BASE}/M
	cd ${BASE}/M
	repo info -l -b Manifest >/dev/null 2>&1 || repo init -u https://android.googlesource.com/platform/manifest -b android-${Mver}
	${NICE} repo sync -j4 2>&1
}

get_lollipop()
{
	#get latest L AOSP into folder called L
	test -d ${BASE}/L || mkdir -p ${BASE}/L
	cd ${BASE}/L
	repo info -l -b Manifest >/dev/null 2>&1 || repo init -u https://android.googlesource.com/platform/manifest -b android-${Lver}
	${NICE} repo sync -j4 2>&1

}

copy_drivers()
{
	#Now that we have them, copy old device sources into M
	${NICE} cp -Rvf ${BASE}/L/device/asus/grouper ${BASE}/M/device/asus/grouper
}

get_blobs()
{
	cd ${BASE}/M
	curl --silent https://dl.google.com/dl/android/aosp/asus-grouper-lmy47v-f395a331.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14466 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/broadcom-grouper-lmy47v-5671ab27.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14464 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/elan-grouper-lmy47v-6a10e8f3.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14490 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/invensense-grouper-lmy47v-ccd43018.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14456 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/nvidia-grouper-lmy47v-c9005750.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14460 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/nxp-grouper-lmy47v-18820f9b.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14452 | tar -xvz
	curl --silent https://dl.google.com/dl/android/aosp/widevine-grouper-lmy47v-e570494f.tgz | tar -xz --to-stdout | dd  iflag=fullblock skip=1 bs=14446 | tar -xvz
}

patch_blobs()
{
	#cool binary patch for GL blobs
	echo -n dmitrygr_libldr | dd bs=1 seek=4340 conv=notrunc of=${BASE}/M/vendor/nvidia/grouper/proprietary/libEGL_tegra.so
	echo -n dgv1 | dd bs=1 seek=6758 conv=notrunc of=${BASE}/M/vendor/nvidia/grouper/proprietary/libEGL_tegra.so
	echo -n dmitrygr_libldr | dd bs=1 seek=3811 conv=notrunc of=${BASE}/M/vendor/nvidia/grouper/proprietary/libGLESv1_CM_tegra.so
	echo -n dgv1 | dd bs=1 seek=6447 conv=notrunc of=${BASE}/M/vendor/nvidia/grouper/proprietary/libGLESv1_CM_tegra.so

	#cool binary patch for GPS blob
	printf "malloc\0" | dd bs=1 seek=5246 conv=notrunc of=${BASE}/M/vendor/broadcom/grouper/proprietary/glgps
}

apply_vendor_patches()
{
	#apply source patch to Nfc package (sadly we must mess with platform code here)
	cd ${BASE}/M/packages/apps/Nfc/
	git apply ${BASE}/patches/packages-apps-Nfc.patch 2>&1

	#apply source patch to vendor repo
	cd ${BASE}/M/vendor
	git apply ${BASE}/patches/vendor.patch 2>&1

	#apply source patch to device repo
	cd ${BASE}/M/device/asus/grouper/grouper
	git apply ${BASE}/patches/device-asus-grouper.patch 2>&1
}


get_kernel()
{
	cd ${BASE}
	${NICE} git clone https://android.googlesource.com/kernel/tegra.git
	cd ${BASE}/tegra
	${NICE} git checkout remotes/origin/android-tegra3-grouper-3.1-lollipop-mr1 -b l-mr1

	#apply kernel patch
	git apply ${BASE}/patches/kernel.patch 2>&1
}


build_kernel()
{
	cd ${BASE}/tegra

	${NICE} make tegra3_android_defconfig
	test -z "${NICE}" && make -j4 || ${NICE} make
	cp ${BASE}/tegra/arch/arm/boot/zImage ${BASE}/M/device/asus/grouper/kernel
}


Typical()
{
	get_marshmallow
	get_lollipop
	copy_drivers
	get_blobs
	patch_blobs
	apply_vendor_patches
	get_kernel
	build_kernel

	#build Android
	cd ${BASE}/M
	source build/envsetup.sh
	${NICE} lunch aosp_grouper-userdebug 2>&1
	${NICE} make ./out/target/product/grouper/symbols/system/bin/tune2fs
	test -z "${NICE}" && make -j4 || ${NICE} make
}

BuildLatest()
{
	# Mver=6.0.0_r1
	latest_M
	Mver=${Mlatest}

	Typical
}

LatestInfo()
{
	if [ -d L -a -d M ]
	then
		grep --no-filename "default revision" L/.repo/manifest.xml M/.repo/manifest.xml
	fi
	
	latest_L
	echo "Most current version of Lollipop is: ${Llatest}"
	latest_M
	echo "Most current version of Marshmallow is: ${Mlatest}"
}

usage()
{
	echo "$0 -[vlnsh]"
	echo "no options will build the system fully"
	echo "    -v [version]          will attempt to download and build the specified Marshmallow release. version format: 6.0.0_r05"
	echo "    -l                    attempts to build the absolute latest release version"
	echo "    -n                    'nicely' build - enables ionice"
	echo "    -s                    displays the latest versions of L and M"
	echo "    -h                    this help"

	exit 1
}

if [ -n "$1" ]; then
    while getopts ":hnslv:" param; do
	case $param in
		s) LatestInfo
			;;
		l) BuildLatest
			;;
                v) Mver=$OPTARG;
                        ;;
                n)  NICE="ionice"
                	;;
		*) usage
			;;
	esac	
    done
fi

Typical
