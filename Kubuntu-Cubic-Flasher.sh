#!/bin/bash
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/Kubuntu-Cubic-Flasher.sh
# 
PROG="${0##*/}"

## This is meant to be run *inside* of the Cubic chroot
# Check to make sure we're inside the right environment

if [ "${HOSTNAME}" != "cubic"  -a "${USER}" != "root" ]
then
	echo "this doesn't look like the cubic chroot environment, aborting"
	echo "Usage:"
	echo " 1) Start cubic"
	echo " 2) choose the project directory"
	echo " 3) choose the Ubuntu iso  ( this script assume 32-bit bionic )"
	echo " 4) customize the names"
	echo " 5) enter into the chroot"
	echo " 6) from an alternate terminal, copy this script into the chroot directory"
	echo " 7) from the chroot, run this script"
	echo " 8) select 'next' until you can 'generate' the ISO"
	echo " 9) copy the ISO to your testing host and boot it."
	echo "10) if it works, huzzah!  Otherwise, you can restart cubic and try additional changes"
	echo "11) eventually you'll get something you like!"
	echo "12) profit"
	exit 1
fi

# you should override this
if [ "${DOMAIN:-example.com}" = "example.com" ]
then
	echo "Warning:  DOMAIN variable not overridden (using '${DOMAIN}' will probably not do what you want)"
	echo ""
	echo "either edit the script, or call it using 'DOMAIN=mydomain.net  ./${PROG}'"
	echo ""
fi

echo -n "Wait 10 seconds or press any key to continue; ctrl-c to abort."
while true
do
	echo -n "."
	read -t 1 -n 1
	if [ $? = 0 ]
	then
		break
	fi
done

echo ""
echo "Here we go!"

# okay, we're good to go, let's make all the changes

cat >/etc/apt/sources.list.d/flashy.list <<EOF
deb http://us.archive.ubuntu.com/ubuntu bionic multiverse
deb http://us.archive.ubuntu.com/ubuntu bionic-updates multiverse
deb http://us.archive.ubuntu.com/ubuntu bionic-security multiverse
deb http://archive.canonical.com/ubuntu bionic partner
deb http://us.archive.ubuntu.com/ubuntu bionic-backports main restricted universe multiverse
EOF

apt update

# flash dependencies
apt -y install flashplugin-downloader browser-plugin-freshplayer-pepperflash
apt-mark hold firefox firefox-locale-en flashplugin-downloader xul-ext-ubufox browser-plugin-freshplayer-pepperflash

# virtualization dependencies
apt -y install virtualbox-guest-dkms virtualbox-guest-utils open-vm-tools-desktop squashfs-tools genisoimage mkisofs zip

# Get the system ready for being live
apt -y upgrade
apt-get -y purge ubiquity ubiquity-frontend-kde ubiquity-casper ubiquity-slideshow-kubuntu ubiquity-ubuntu-artwork

apt-get autoclean
apt-get autoremove

# This may need to be cached

test -r flash_player_npapi_linux.i386.tar.gz ||  \
     wget https://fpdownload.adobe.com/get/flashplayer/pdc/32.0.0.465/flash_player_npapi_linux.i386.tar.gz
#   or  https://fpdownload.adobe.com/get/flashplayer/pdc/32.0.0.465/flash_player_npapi_linux.x86_64.tar.gz
# * archived on https://www.denali.net/Flash/[name]

tar -C / -xpvf flash_player_npapi_linux.i386.tar.gz
rm -rf /LGPL /readme.txt /license.pdf
mkdir -p /usr/lib/mozilla/plugins
mv /libflashplayer.so /usr/lib/mozilla/plugins
sed -i.EOL 's/\x00\x00\x40\x46\x3E\x6F\x77\x42/\x00\x00\x00\x00\x00\x00\xF8\x7F/' /usr/lib/mozilla/plugins/libflashplayer.so

##  this configures Firefox policies for your needs:
mkdir -p /etc/firefox/policies/ \
	/usr/lib/firefox/defaults/pref/ \
	/usr/lib/firefox/defaults/profile/ \
	/usr/lib/firefox/browser/defaults/preferences/ \
	/usr/lib/firefox/distribution/

cat > /etc/firefox/prefs.js <<EOF
// Lots of changes for Enterprise-ish security
lockPref("app.normandy.first_run", false);
lockPref("app.normandy.migrationsApplied", 10);
lockPref("app.normandy.startupRolloutPrefs.doh-rollout.enabled", false);
lockPref("app.shield.optoutstudies.enabled", false);
lockPref("app.update.enabled", false);
lockPref("app.update.auto", false);
lockPref("app.update.mode", 0);
lockPref("app.update.service.enabled", false);
lockPref("browser.bookmarks.restore_default_bookmarks", false);
lockPref("browser.discovery.enabled", false);
lockPref("browser.laterrun.enabled", true);
lockPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
lockPref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
lockPref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
lockPref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
lockPref("browser.newtabpage.activity-stream.feeds.snippets", false);
lockPref("browser.newtabpage.activity-stream.feeds.topsites", false);
lockPref("browser.newtabpage.activity-stream.showSearch", false);
lockPref("browser.newtabpage.enabled", false);
pref("browser.rights.3.shown", true);
lockPref("browser.search.hiddenOneOffs", "Amazon.com,Bing,DuckDuckGo,eBay,Wikipedia (en)");
lockPref("browser.search.region", "US");
lockPref("browser.search.suggest.enabled", false);
lockPref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.homepage_override.mstone","ignore");
lockPref("browser.startup.homepage", "about:blank");
lockPref("browser.startup.page", 3);
lockPref("browser.urlbar.placeholderName", "Google");
lockPref("browser.urlbar.suggest.topsites", false);
lockPref("datareporting.healthreport.service.enabled", false);
lockPref("datareporting.healthreport.uploadEnabled", false);
lockPref("datareporting.policy.dataSubmissionEnabled", false);
lockPref("doh-rollout.balrog-migration-done", true);
lockPref("doh-rollout.disable-heuristics", true);
lockPref("doh-rollout.doneFirstRun", true);
lockPref("doh-rollout.skipHeuristicsCheck", true);
clearPref("extensions.lastAppVersion");
lockPref("extensions.pendingOperations", false);
lockPref("extensions.ui.dictionary.hidden", true);
lockPref("extensions.ui.locale.hidden", true);
lockPref("extensions.update.autoUpdateDefault", false);
lockPref("extensions.webcompat.perform_injections", true);
lockPref("extensions.webcompat.perform_ua_overrides", true);
lockPref("media.eme.enabled", true);
lockPref("media.gmp-gmpopenh264.abi", "x86-gcc3");
lockPref("media.gmp-widevinecdm.abi", "x86-gcc3");
lockPref("network.proxy.backup.ftp", "10.0.0.1");
lockPref("network.proxy.backup.ftp_port", 443);
lockPref("network.proxy.backup.ssl", "10.0.0.1");
lockPref("network.proxy.backup.ssl_port", 443);
lockPref("network.proxy.ftp", "10.0.0.1");
lockPref("network.proxy.ftp_port", 443);
lockPref("network.proxy.http", "10.0.0.1");
lockPref("network.proxy.http_port", 443);
lockPref("network.proxy.no_proxies_on", "<local>, 10.0.0.0/8, 192.168.0.0/16, 172.16.0.0/12, ${DOMAIN}, *.${DOMAIN}");
lockPref("network.proxy.share_proxy_settings", true);
lockPref("network.proxy.ssl", "203.0.113.254");
lockPref("network.proxy.ssl_port", 443);
lockPref("network.proxy.type", 1);
lockPref("network.trr.mode", 5);
pref("plugins.notifyMissingFlash", false);
lockPref("plugins.hide_infobar_for_outdated_plugin", true);
clearPref("plugins.update.url");
lockPref("plugin.flash.blockliststate", 0);
lockPref("services.sync.clients.lastSync", "0");
lockPref("signon.autofillForms", false);
lockPref("signon.generation.enabled", false);
lockPref("signon.management.page.breach-alerts.enabled", false);
lockPref("signon.rememberSignons", false);
lockPref("toolkit.telemetry.reportingpolicy.firstRun", false);
lockPref("toolkit.crashreporter.enabled", false);
lockPref("trailhead.firstrun.didSeeAboutWelcome", true);
EOF

ln -s /etc/firefox/prefs.js /usr/lib/firefox/defaults/profile/user.js
ln -s /etc/firefox/prefs.js /usr/lib/firefox/defaults/pref/all-flashy.js
ln -s /etc/firefox/prefs.js /usr/lib/firefox/browser/defaults/preferences/autoconfig.js

# per https://github.com/mozilla/policy-templates/blob/v2.1/README.md  (for FF 79)
cat > /etc/firefox/policies/policies.json <<EOF
# Disable things for security reasons
{
    "policies": {
	"AppAutoUpdate": false
	"Certificates": {
		"ImportEnterpriseRoots": true
	}
	"DisableMasterPasswordCreation": true
	"DisableAppUpdate": true
	"DisableFirefoxAccounts": true
	"DisableFirefoxStudies": true 
	"DisableFormHistory": true
	"DisableForgetButton": true
	"DisableFormHistory": true
	"DisablePasswordReveal": true
	"DisablePocket": true
	"DisableProfileRefresh": true
	"DisableSystemAddonUpdate": true
	"DisableTelemetry": true
	"DNSOverHTTPS": {
		"Enabled":  false,
		"Locked": true
	}
	"DontCheckDefaultBrowser": true 
	"ExtensionUpdate": false
	"FlashPlugin": {
		"Default": true,
		"Locked": true
	}
	"Homepage": {
		"URL": "https://www.google.com/",
		"Locked": true,
		"StartPage": "previous-session"
	}
	"OfferToSaveLoginsDefault": false
	"OverrideFirstRunPage": ""
	"OverridePostUpdatePage": ""
	"PasswordManagerEnabled": false
	"Proxy": {
		"Mode": "manual",
		"Locked": true,
		"HTTPProxy": "https://203.0.113.254",
		"Passthrough": "<local>, 10.0.0.0/8, 192.168.0.0/16, 172.16.0.0/12, *.${DOMAIN}, ${DOMAIN}"
		"UseHTTPProxyForAllProtocols": true,
		"UseProxyForDNS": false
	}
	"UserMessaging": {
		"WhatsNew": false,
		"ExtensionRecommendations": false,
		"FeatureRecommendations": false,
		"UrlbarInterventions": false
	}

    }
}

EOF

ln -s /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/


echo "The last step is to remove temp files, history, and ALL PACKAGE MANAGERS"
echo -n "Wait 10 seconds or press any key to continue; ctrl-c to abort."
while true
do
	echo -n "."
	read -t 1 -n 1
	if [ $? = 0 ]
	then
		break
	fi
done

rm -f /root/.bash_history /root/.*~ /root/.joe*
rm -f /usr/bin/dpkg* /usr/bin/apt* /etc/alternatives/apt*

echo "Complete!  continue building your iso"
