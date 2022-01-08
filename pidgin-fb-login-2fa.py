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

DEBUG = False

# We interrupt to include prpl-facebook-config-parse before our regularly scheduled program

home = str(Path.home())
ACCOUNTS=home + "/.purple/accounts.xml"

print("accounts.xml is: ", ACCOUNTS)

with open(ACCOUNTS, 'r') as myfile:
    obj = xmltodict.parse(myfile.read())

acts=obj["account"]["account"]

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

EMAIL=acts[idx]["name"]
passwd=acts[idx]["password"]


settings=acts[idx]["settings"]

found=0
ox=0
while 1:
    ix=0
    while 1:
        try:
            if settings[ox]["setting"][ix]["@name"] == "did":
                MACHINE_ID=settings[ox]["setting"][ix]["#text"]
                found = found +1
            
            if settings[ox]["setting"][ix]["@name"] == "uid":
                UID=settings[ox]["setting"][ix]["#text"]
                found = found +1

            if found > 1:
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

if found == 0:
    print("Either no machine account (did) or user account (uid) found in prpl-facebook section of ", ACCOUNTS)
    print("exiting")
    exit(1)



# ================================
# pidgin-fb-login-test.py follows

FB_API_KEY = '256002347743983'
FB_API_SECRET = '374e60f8b9bb6b8cbb30f78030438895'

def fb_sig(data):
    newdata = data.copy()
    params = ''.join(['%s=%s' % x for x in sorted(data.items())])
    newdata['sig'] = hashlib.md5((params + FB_API_SECRET).encode('utf-8')).hexdigest()
    return newdata

def debug(msg):
    global DEBUG
    if DEBUG:
        print("DEBUG: %s", msg)

if EMAIL == '':
    print("ERROR: set an email address, please")
    sys.exit()

if MACHINE_ID == '':
    print("ERROR: set a machine id (to any UUID), please")
    sys.exit()

parser = OptionParser()
parser.add_option('-d', '--debug', action='store_true', dest='debug', default=False)
(options, args) = parser.parse_args()

if options.debug:
    DEBUG = True

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
    "device_id": MACHINE_ID,
}

print('''Access Token generator for Facebook 2factor login

This tool will perform 2-factor login to FB and then print out an
access token needed for the FB plugin for bitlbee and pidgin. Take
the resulting code and put it in the "token" tag in accounts.xml
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
response = json.loads(response_data)
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
#code = getpass.getpass('Code: ')

error_data = json.loads(response['error_data'])
first_fac = error_data['login_first_factor']

data['credentials_type'] = 'two_factor'
data['error_detail_type'] = 'button_with_disabled'
data['first_factor'] = first_fac
data['twofactor_code'] = code
data['password'] = data['twofactor_code']
data['userid'] = error_data['uid']
data['machine_id'] = error_data['machine_id']

params = urlencode(fb_sig(data))
conn.request('POST', '/method/auth.login', params, headers)
response = conn.getresponse()
debug("status, reason: %s, %s" % (response.status, response.reason))
response_data = response.read()
debug("undecoded response: %s" % response_data)
response = json.loads(response_data)

print("Access token:", response['access_token'])
