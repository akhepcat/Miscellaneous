#!/bin/python3
# requires: https://github.com/iMicknl/python-sagemcom-api
# Portions of this script directly from iMicknl's example
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/sagemcom-stats.py

import asyncio
import json
import ast
import sys
from sagemcom_api.enums import EncryptionMethod
from sagemcom_api.client import SagemcomClient

HOST = "192.168.100.1"
USERNAME = "admin"
PASSWORD = ""
DEBUG = False

# EncryptionMethod.MD5 or EncryptionMethod.SHA512;  FAST3896 needs SHA512
ENCRYPTION_METHOD = EncryptionMethod.SHA512

def debug(msg):
    global DEBUG
    if DEBUG:
        print("DEBUG: ", msg)


async def main() -> None:
    async with SagemcomClient(HOST, USERNAME, PASSWORD, ENCRYPTION_METHOD, ssl=True, verify_ssl=False) as client:
        try:
            await client.login()
        except Exception as exception:  # pylint: disable=broad-except
            print(exception)
            return

        # Print device information of Sagemcom F@st router
        device_info = await client.get_device_info()
        print(f"{device_info.id} {device_info.model_name}")

        custom_command_output = await client.get_value_by_xpath("Device/Docsis/CableModem/Status")
        if custom_command_output == "OPERATIONAL" :

            # Get the Downstream data
            custom_command_output = await client.get_value_by_xpath("Device/Docsis/CableModem/Downstreams")
            debug(custom_command_output)
            ourjson = json.loads(json.dumps(ast.literal_eval( str(custom_command_output) )))
            for idx in range(len(ourjson)):
                response = ourjson[idx]
                print("DS%i -> chan: %i, freq: %0.3f MHz, siglock: %s, snr: %0.03f dB, pwr: %0.03f dBmv, errs: %0.03f%%" % 
                    (response['uid'], response['channel_id'], response['frequency'] / 1000000, response['lock_status'],
                    response['SNR'], response['power_level'], response['uncorrectable_codewords'] / response['unerrored_codewords'] * 100) )

            # Get the Upstream data
            custom_command_output = await client.get_value_by_xpath("Device/Docsis/CableModem/Upstreams")
            debug(custom_command_output)
            ourjson = json.loads(json.dumps(ast.literal_eval( str(custom_command_output) )))
            for idx in range(len(ourjson)):
                response = ourjson[idx]
                print("US%i -> chan: %i, freq: %0.3f MHz, pwr: %0.03f dBmv" % (response['uid'], response['channel_id'], response['frequency'] / 1000000, response['power_level']) )
        else:
            print("Cablemodem doesn't appear operational")

###### Main section

arguments = len(sys.argv) - 1
if (arguments > 0):
    PASSWORD = sys.argv[1]

asyncio.run(main())

########################################################

# Above paths discovered by using the chrome developer console, and typing '$.xpaths' and looking for various values
# Other browser console commands for feature hunting; log into the web console first via the browser

# $.config
# $.xpaths
# $.xmo.getValuesTree("*")
# $.xmo.getValuesTree("*/*")
# $.xmo.getValuesTree("*/*/*")
# $.xmo.getValuesTree("*/*/*/*")
# $.xmo.getValuesTree("*/*/*/*/*")
# $.xmo.getValuesTree("*/*/*/*/*/*")
# $.xmo.getValuesTree("*/*/*/*/*/*/*")
# $.xmo.getCapability("*")
# $.xmo.getCapability("*/*")
# $.xmo.getCapability("*/*/*")
# $.xmo.getValuesTree($.xpaths.mySagemcomBox);

# Using the xpaths lets us query values within the API, and return interesting data

# For instance, the docsis data is composed of many records like:
# DS: [{'uid': 1, 'channel_id': 24, 'lock_status': True, 'frequency': 657000000.0, 
#	'SNR': 41.0, 'power_level': 1.0, 'modulation': 'Qam256', 'band_width': 6000000,
#	'unerrored_codewords': 2536679702, 'correctable_codewords': 653402, 'uncorrectable_codewords': 1475, 'symbol_rate': 5360}, 
#
# US: [{'uid': 1, 'channel_id': 13, 'lock_status': True, 'frequency': 34800000.0, 'symbol_rate': 5120,
#	'power_level': 49.299999, 'modulation': 'Qam16', 'profile_id31': '', 'modulation31': '', 'frequency31': ''},

