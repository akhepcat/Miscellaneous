#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/Kubuntu-Cubic-Flasher.sh
# 
PROG="${0##*/}"

pause() {
	LOOP=${1:-5}
	msg="${2:-Sleeping for $LOOP seconds, any key to continue, or ctrl-c to break}"

	echo -n "${msg}"
	while true
	do
		if [ ${LOOP} -lt 1 ]
		then
			break
		else
			LOOP=$((LOOP - 1))
		fi
		echo -n "."
		read -t 1 -n 1
		if [ $? = 0 ]
		then
			break
		fi
	done
}

usage() {
	cat <<EOF
Usage:
  v) create an optional 'custom.sh' script to install localized packages, or make configuration changes in the system
 iv) create an optional 'certificates.tar' archive of CA certs to inject as trusted by the system/browser
iii) create an optional 'remove.pkgs' text list of packages to remove from the system
 ii) define alternate env vars for DOMAIN or OKCIDRS variables as needed (default: ${DOMAIN:-example.com},  RFC1918)
  i) specify an alternate env var for FLASHURL to download ${flash} from

  1) Start cubic
  2) choose the project directory
  3) choose the Ubuntu iso  (this script assumes 64-bit bionic )
  4) customize the names
  5) enter into the chroot
  6) from an alternate terminal, copy this script (and optional files) into the chroot directory
  7) from the chroot, run this script
  8) select 'next' until you can 'generate' the ISO
  9) copy the ISO to your testing host and boot it.
 10) if it works, huzzah!  Otherwise, you can restart cubic and try additional changes
 11) eventually you'll get something you like!
 12) profit
EOF

}

# This may need to be cached
if [ "$(uname -m)" = "x86_64" ];
then
	flash="flash_player_npapi_linux.x86_64.tar.gz"
else
	flash="flash_player_npapi_linux.i386.tar.gz"
fi

# we don't use args, so any args are 'help'
if [ -n "$1" ]
then
	usage
	exit 1
fi

## This is meant to be run *inside* of the Cubic chroot
# Check to make sure we're inside the right environment
if [ "${HOSTNAME}" != "cubic"  -a "${USER}" != "root" ]
then
cat <<EOF
Error: this doesn't look like the cubic chroot environment, aborting
${PROG} --help
EOF
	exit 1
fi

# This prevents the user from browsing outside an enterprise.
# Setting this to '0.0.0.0/0' will allow Internet browsing, which may not be good!
RFC1918="10.0.0.0/8 192.168.0.0/16 172.16.0.0/12"
OKCIDRS=${OKCIDRS:-$RFC1918}
if [ "${OKCIDRS}" = "${RFC1918}" ]
then
	echo "Info:  OKCIDRS is ${OKCIDRS// /, }"
	echo ""
	echo "change using 'OKCIDRS=\"C.I.D.R/1 [c.i.d.r/2 c.i.d.r/3 ...]\"  ./${PROG}'"
	echo ""
fi
for net in ${OKCIDRS}
do
	IPRANGE="${IPRANGE:+$IPRANGE, $net}"
done

if [ "${DOMAIN:-example.com}" = "example.com" ]
then
	echo "WARN:  DOMAIN variable not overridden (using '${DOMAIN}' will probably not do what you want)"
	echo ""
	echo "change using 'DOMAIN=\"mydomain.net [2nd.tld 3rd.tld ...]\"  ./${PROG}'"
	echo ""
else
	echo "Info:  DOMAIN is ${DOMAIN// /, }"
fi
for tld in ${DOMAIN}
do
	DOMAINLIST="${DOMAINLIST:+$DOMAINLIST, *.$tld, $tld}"
done
PROXY="127.127.127.127"
PROXYPORT="127"

pause 10
echo -e "\nHere we go!\n"

# okay, we're good to go, let's make all the changes

echo "11) Configuring repositories"
cat >/etc/apt/sources.list.d/flashy.list <<EOF
deb http://us.archive.ubuntu.com/ubuntu bionic multiverse
deb http://us.archive.ubuntu.com/ubuntu bionic-updates multiverse
deb http://us.archive.ubuntu.com/ubuntu bionic-security multiverse
deb http://archive.canonical.com/ubuntu bionic partner
deb http://us.archive.ubuntu.com/ubuntu bionic-backports main restricted universe multiverse
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null 2>&1

aptq='apt-get -qq -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold"'
# flash dependencies
echo "10) Installing flash dependencies, and holding specific packages back from upgrade"
${aptq} install flashplugin-downloader browser-plugin-freshplayer-pepperflash >/dev/null 2>&1
apt-mark hold firefox firefox-locale-en flashplugin-downloader xul-ext-ubufox browser-plugin-freshplayer-pepperflash >/dev/null 2>&1

# make firefox use system certificates
${aptq} install libnss3-tools p11-kit-modules p11-kit libnss3 >/dev/null 2>&1
for nss in $(find / -mount -type f -name "libnssckbi.so")
do
	mv ${nss} ${nss}.dist
	ln -s /usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-trust.so ${nss}
done

# Virtualization dependencies
echo "9) Installing virtualization support"
${aptq} install virtualbox-guest-dkms virtualbox-guest-utils open-vm-tools-desktop squashfs-tools genisoimage mkisofs zip >/dev/null 2>&1

# MS Hyper-V
for i in hv_vmbus hv_storvsc hv_blkvsc hv_netvsc hv_sock hv_utils
do
	echo $i >> /etc/modules
done

# Get the system ready for being live
echo "8) Upgrading the live system"
${aptq} upgrade >/dev/null 2>&1
${aptq} autoclean >/dev/null 2>&1
${aptq} autoremove >/dev/null 2>&1

# Don't download if it's already cached
echo "7) Installing and patching Adobe Flash player"
FLASHURL=${FLASHURL:-https://fpdownload.adobe.com/get/flashplayer/pdc/32.0.0.465}
wget --quiet --no-clobber ${FLASHURL}/${flash}
if [ -r "${flash}" ]
then
	tar -C / -xpf ${flash}
	rm -rf /LGPL /readme.txt /license.pdf
	mkdir -p /usr/lib/mozilla/plugins
	mv /libflashplayer.so /usr/lib/mozilla/plugins
	sed -i.EOL 's/\x00\x00\x40\x46\x3E\x6F\x77\x42/\x00\x00\x00\x00\x00\x00\xF8\x7F/' /usr/lib/mozilla/plugins/libflashplayer.so
else
	echo "Flash was unable to be downloaded, and is not locally cached."
	echo "Aborting so you can manually download a copy of ${flash} (32.0.0.465 only) into this directory and restart"
	exit 1
fi

## If you have custom certificates, they'll be added here:
echo "6) Updating CA certificates"
if [ -r "certificates.tar" ]
then
	tar -C /usr/local/share/ca-certificates -xf certificates.tar
	update-ca-certificates >/dev/null 2>&1
fi


##  this configures Firefox policies for your needs:
echo "5) Configuring Firefox policies"
mkdir -p /etc/firefox/policies/ \
	/usr/lib/firefox/defaults/pref/ \
	/usr/lib/firefox/defaults/profile/ \
	/usr/lib/firefox/browser/defaults/preferences/ \
	/usr/lib/firefox/distribution/

cat > /etc/firefox/prefs.js <<EOF
// Lots of changes for Enterprise-ish security
pref("app.normandy.first_run", false);
pref("app.normandy.migrationsApplied", 10);
pref("app.normandy.startupRolloutPrefs.doh-rollout.enabled", false, locked);
pref("app.shield.optoutstudies.enabled", false, locked);
pref("app.update.enabled", false, locked);
pref("app.update.auto", false, locked);
pref("app.update.mode", 0, locked);
pref("app.update.service.enabled", false, locked);
pref("browser.bookmarks.restore_default_bookmarks", false, locked);
pref("browser.discovery.enabled", false, locked);
pref("browser.laterrun.enabled", true, locked);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false, locked);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false, locked);
pref("browser.newtabpage.activity-stream.feeds.section.highlights", false, locked);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false, locked);
pref("browser.newtabpage.activity-stream.feeds.snippets", false, locked);
pref("browser.newtabpage.activity-stream.feeds.topsites", false, locked);
pref("browser.newtabpage.activity-stream.showSearch", false, locked);
pref("browser.newtabpage.enabled", false, locked);
pref("browser.rights.3.shown", true);
pref("browser.search.hiddenOneOffs", "Amazon.com,Bing,DuckDuckGo,eBay,Wikipedia (en)");
pref("browser.search.region", "US", locked);
pref("browser.search.suggest.enabled", false, locked);
pref("browser.shell.checkDefaultBrowser", false, locked);
pref("browser.startup.homepage_override.mstone","ignore", locked);
pref("browser.startup.homepage", "about:blank", locked);
pref("browser.startup.page", 3, locked);
pref("browser.urlbar.placeholderName", "Google", locked);
pref("browser.urlbar.suggest.topsites", false, locked);
pref("datareporting.healthreport.service.enabled", false, locked);
pref("datareporting.healthreport.uploadEnabled", false, locked);
pref("datareporting.policy.dataSubmissionEnabled", false, locked);
pref("doh-rollout.balrog-migration-done", true, locked);
pref("doh-rollout.disable-heuristics", true, locked);
pref("doh-rollout.doneFirstRun", true, locked);
pref("doh-rollout.skipHeuristicsCheck", true, locked);
pref("extensions.lastAppVersion","");
pref("extensions.pendingOperations", false, locked);
pref("extensions.ui.dictionary.hidden", true, locked);
pref("extensions.ui.locale.hidden", true, locked);
pref("extensions.update.autoUpdateDefault", false, locked);
pref("extensions.webcompat.perform_injections", true, locked);
pref("extensions.webcompat.perform_ua_overrides", true, locked);
pref("media.eme.enabled", true, locked);
pref("media.gmp-gmpopenh264.abi", "x86-gcc3", locked);
pref("media.gmp-widevinecdm.abi", "x86-gcc3", locked);
pref("network.proxy.backup.ftp", "${PROXY}", locked);
pref("network.proxy.backup.ftp_port", ${PROXYPORT}, locked);
pref("network.proxy.backup.ssl", "${PROXY}", locked);
pref("network.proxy.backup.ssl_port", ${PROXYPORT}, locked);
pref("network.proxy.ftp", "${PROXY}", locked);
pref("network.proxy.ftp_port", ${PROXYPORT}, locked);
pref("network.proxy.http", "${PROXY}", locked);
pref("network.proxy.http_port", ${PROXYPORT}, locked);
pref("network.proxy.no_proxies_on", "<local>, ${IPRANGE:+$IPRANGE,} ${DOMAINLIST}", locked);
pref("network.proxy.share_proxy_settings", true, locked);
pref("network.proxy.ssl", "${PROXY}", locked);
pref("network.proxy.ssl_port", ${PROXYPORT}, locked);
pref("network.proxy.type", 1, locked);
pref("network.trr.mode", 5, locked);
pref("plugins.notifyMissingFlash", false, locked);
pref("plugins.hide_infobar_for_outdated_plugin", true, locked);
pref("plugins.update.url","");
pref("plugin.flash.blockliststate", 0, locked);
pref("services.sync.clients.lastSync", "0", locked);
pref("signon.autofillForms", false, locked);
pref("signon.generation.enabled", false, locked);
pref("signon.management.page.breach-alerts.enabled", false, locked);
pref("signon.rememberSignons", false, locked);
pref("toolkit.telemetry.reportingpolicy.firstRun", false, locked);
pref("toolkit.crashreporter.enabled", false, locked);
pref("trailhead.firstrun.didSeeAboutWelcome", true, locked);
EOF

ln -s /etc/firefox/prefs.js /usr/lib/firefox/defaults/profile/user.js >/dev/null 2>&1
ln -s /etc/firefox/prefs.js /usr/lib/firefox/defaults/pref/all-flashy.js >/dev/null 2>&1
ln -s /etc/firefox/prefs.js /usr/lib/firefox/browser/defaults/preferences/autoconfig.js >/dev/null 2>&1
mkdir -p /etc/skel/Desktop/ && ln -s /usr/share/applications/firefox.desktop /etc/skel/Desktop/ >/dev/null 2>&1

# tell firefox to install the certs via policy
for crt in $(ls /usr/local/share/ca-certificates/*.crt)
do
	CERT="${CERT:+$CERT, }\"$crt\""
done

# per https://github.com/mozilla/policy-templates/blob/v2.1/README.md  (for FF 79)
# Disable things for security reasons
cat > /etc/firefox/policies/policies.json <<EOF
{
    "policies": {
	"AppAutoUpdate": false,
	"Certificates": {
		"ImportEnterpriseRoots": true${CERT:+,}
		${CERT:+"Install": [$CERT]}
	},
	"DisableMasterPasswordCreation": true,
	"DisableAppUpdate": true,
	"DisableFirefoxAccounts": true,
	"DisableFirefoxStudies": true ,
	"DisableFormHistory": true,
	"DisableForgetButton": true,
	"DisableFormHistory": true,
	"DisablePasswordReveal": true,
	"DisablePocket": true,
	"DisableProfileRefresh": true,
	"DisableSystemAddonUpdate": true,
	"DisableTelemetry": true,
	"DNSOverHTTPS": {
		"Enabled":  false,
		"Locked": true
	},
	"DontCheckDefaultBrowser": true ,
	"ExtensionUpdate": false,
	"FlashPlugin": {
		"Default": true,
		"Locked": true
	},
	"Homepage": {
		"URL": "about:blank",
		"Locked": true,
		"StartPage": "previous-session"
	},
	"OfferToSaveLoginsDefault": false,
	"OverrideFirstRunPage": "",
	"OverridePostUpdatePage": "",
	"PasswordManagerEnabled": false,
	"Proxy": {
		"Mode": "manual",
		"Locked": true,
		"HTTPProxy": "${PROXY}:${PROXYPORT}",
		"Passthrough": "<local>, ${IPRANGE:+$IPRANGE,} ${DOMAINLIST}",
		"UseHTTPProxyForAllProtocols": true,
		"UseProxyForDNS": false
	},
	"UserMessaging": {
		"WhatsNew": false,
		"ExtensionRecommendations": false,
		"FeatureRecommendations": false,
		"UrlbarInterventions": false
	}

    }
}

EOF

ln -s /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/ >/dev/null 2>&1

# Perform any custom configuration, package adding, etc...
echo "4) Checking for custom.sh"
if [ -r "./custom.sh" ]
then
	echo "custom.sh found, executing..."
	bash ./custom.sh
	rm -f ./custom.sh
fi

# Remove the liveCD installer option
echo "3) Removing the live installer"
${aptq} purge ubiquity ubiquity-frontend-kde ubiquity-casper ubiquity-slideshow-kubuntu ubiquity-ubuntu-artwork >/dev/null 2>&1

# Remove optional packages
opks=$(wc -l "./remove.pkgs" >/dev/null 2>&1)
echo "2) Removing ${opks:-0} optional packages"
if [ -r "./remove.pkgs" ]
then
	dpkg -r --no-triggers --force-confdef --force-confold --force-breaks --force-depends $(cat ./remove.pkgs) >/dev/null 2>&1
fi

echo "1) The last step is to remove temp files, history, compilers, external filesystem drivers, and ALL PACKAGE MANAGERS"
pause 10
echo -e "\nCleaning up..."
rm -f /usr/bin/dpkg* /usr/bin/apt* /usr/bin/x86_64-linux-gnu-{as,cpp*,g++*,gcc*,ld*,obj*} /usr/bin/gdb  /etc/alternatives/apt*

echo "0) Complete!  continue building your iso"
rm -f /root/*
