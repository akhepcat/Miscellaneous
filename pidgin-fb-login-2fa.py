#!/usr/bin/python3
# Portions of this script directly from https://gist.github.com/jaymzh/3ed8817cf8c20222ca09ce33a544b695
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/pidgin-fb-login-2fa.py

import sys
import cgi
from urllib.parse import urlencode, quote_plus
import hashlib
import getpass
import http.client
import urllib
import json
import xmltodict
from pathlib import Path
from optparse import OptionParser


FB_API_KEY = '256002347743983'
FB_API_SECRET = '374e60f8b9bb6b8cbb30f78030438895'
DEBUG = False


# Somehelper methods
def fb_sig(data):
    newdata = data.copy()
    params = ''.join(['%s=%s' % x for x in sorted(data.items())])
    newdata['sig'] = hashlib.md5((params + FB_API_SECRET).encode('utf-8')).hexdigest()
    return newdata

def debug(msg):
    global DEBUG
    if DEBUG:
        print("DEBUG: %s", msg)


parser = OptionParser()
parser.add_option('-d', '--debug', action='store_true', dest='debug', default=False)
(options, args) = parser.parse_args()

if options.debug:
    DEBUG = True

home = str(Path.home())
ACCOUNTS = home + "/.purple/accounts.xml"

debug("accounts.xml is: %s" % ACCOUNTS)

with open(ACCOUNTS, 'r') as myfile:
    obj = xmltodict.parse(myfile.read())

acts = obj["account"]["account"]

found=0
idx=0
while found == 0:
    if acts[idx]["protocol"] == "prpl-facebook":
        found=1
    else:
        idx = idx + 1

if found == 0:
    print("No prpl-facebook account found in ", ACCOUNTS)
    print("exiting")
    exit(1)

EMAIL = acts[idx]["name"]
passwd = acts[idx]["password"]
settings = acts[idx]["settings"]

### Get did, uid, mid
found=0
ox=0
while 1:
    ix=0
    while 1:
        debug("Checking ox %s ix %s, it is %s" % (ox, ix, settings[ox]["setting"][ix]["@name"]))
        try:
            if settings[ox]["setting"][ix]["@name"] == "did":
                DID = settings[ox]["setting"][ix]["#text"]
                found = found +1
            
            if settings[ox]["setting"][ix]["@name"] == "uid":
                UID = settings[ox]["setting"][ix]["#text"]
                found = found +1

            if settings[ox]["setting"][ix]["@name"] == "mid":
                MID = settings[ox]["setting"][ix]["#text"]
                found = found +1

            if found > 2:
                break

        except:
            break

        ix = ix + 1
        if ix > 10:
            break

    if found < 2:
        ox = ox + 1
    else:
        break

    if ox > 20:
        break

if found < 3:
    print("Warning: Either no machine (mid), device (did) or user account (uid) found in prpl-facebook section of ", ACCOUNTS)
    print("This may cause unexpected errors in the script")
    # exit(1)

debug("Account UID: %s" % UID)
debug("Account DID: %s" % DID)
debug("Account MID: %s" % MID)


if EMAIL == '':
    print("ERROR: set an email address, please")
    sys.exit()

if DID == '':
    print("ERROR: set a device id (to any UUID), please")
    sys.exit()

data = {
    "fb_api_req_friendly_name": "authenticate",
    "locale": "en",
    "format": "json",
    "api_key": FB_API_KEY,
    "method": "auth.login",
    "generate_session_cookies": "1",
    "generate_machine_id": "1",
    "email": EMAIL,
    "uid": UID,
    "device_id": DID,
}

print('''Access Token generator for Facebook 2factor login

Make sure Pidgin is *not running* before proceeding. Pidgin modifies
the accounts.xml on exit as well as while running, so it is important
to exit pidgin before starting so our changes are not lost.

This tool will perform 2-factor login to FB and then print out an
access token needed for the FB plugin for bitlbee and pidgin.

Do *NOT* select "yes this was me" if you get a security pop-up from
your Facebook app. Instead, enter the code in here.

Take the resulting code and put it in the "token" tag in accounts.xml like so:

      <token type='string'>THE_CODE_HERE</token>
''')

data['password'] = passwd

headers = {"Content-type": "application/x-www-form-urlencoded", "Accept": "*/*"}
conn = http.client.HTTPSConnection('b-api.facebook.com:443')
params = urlencode(fb_sig(data), quote_via=quote_plus)
conn.request('POST', '/method/auth.login', params, headers)
response = conn.getresponse()
debug("status, reason: %s, %s" % (response.status, response.reason))
response_data = response.read()
debug("undecoded response: %s" % response_data)
response = json.loads(response_data.decode('utf-8'))
debug(response)

# check to make sure that worked...
if response['error_code'] != 406:
    print(
        "ERROR: Incorrect password, 2-fac is not enabled, or some other issue."
        " Dumping results:\n\n\t",
        end=''
    )
    print(response)
    sys.exit(1)

code = input('Code: ')

error_data = json.loads(response['error_data'])
first_fac = error_data['login_first_factor']

data['credentials_type'] = 'two_factor'
data['error_detail_type'] = 'button_with_disabled'
data['first_factor'] = first_fac
data['twofactor_code'] = code
data['password'] = data['twofactor_code']
data['userid'] = error_data['uid']
data['machine_id'] = error_data['machine_id']

debug("FB Account UID: %s" % error_data['uid'] )
try:
    data['device_id'] = error_data['device_id']
    debug("FB Account DID: %s" % error_data['device_id'])
except:
    print("FB Account DID not present in error_data: equal to accounts.xml did")

debug("FB Account MID: %s" % error_data['machine_id'])


params = urlencode(fb_sig(data))
conn.request('POST', '/method/auth.login', params, headers)
response = conn.getresponse()
debug("status, reason: %s, %s" % (response.status, response.reason))
response_data = response.read()
debug("undecoded response: %s" % response_data)
response = json.loads(response_data.decode('utf-8'))

print("Update or add the following settings in %s under the Facebook account:", ACCOUNTS)

print("<setting name='token' type='string'>%s</setting>" % response['access_token'])

# Pidgin initializes UID to 0...
if UID == 0:
    print("<setting name='uid' type='string'>%s</setting>" % response['uid'])

# We don't always get back a "device_id", but if we do, make sure it's correct
remote_did = response.get('device_id')
if ( remote_did is not None and DID != response.get('device_id') ):
    print("<setting name='did' type='string'>%s</setting>" % response['device_id'])

if ( MID != response['machine_id'] ):
    print("<setting name='mid' type='string'>%s</setting>" % response['machine_id'])
