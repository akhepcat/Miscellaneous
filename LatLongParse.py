#!/usr/bin/python
# input:  csv of lat,long  figures
# output: csv of lat,long,city,state,country  
#
# Requires:  pip install opencage

from opencage.geocoder import OpenCageGeocode
import sys
import ast

key = '3a9c236e3fea4aef83d42291e906ef48'	# use your own key
latlongfile = 'latlongs.csv'

geocoder = OpenCageGeocode(key)

try: 
  with open(latlongfile,'r') as f:
    for line in f:
      try:
        latlong = line.strip()
        latitude_s,longitude_s = latlong.split(',')

        latitude  = ast.literal_eval(latitude_s)
        longitude = ast.literal_eval(longitude_s)

        # 2500 lookups per day on the "free" plan
        result = geocoder.reverse_geocode(latitude, longitude, language='en', no_annotations='1')

        try:
          city    = result[0]['components']['city']
        except:
          city    = "n/a"

        try:
          state   = result[0]['components']['state']
        except:
          state    = "n/a"

        try:
          country = result[0]['components']['country_code'].upper()
        except:
          country    = "n/a"

        print('%f,%f,%s,%s,%s' % (latitude, longitude, city, state, country))
      except:
        pass  # ignore empty lines

except IOError:
  print('Error: File %s does not appear to exist.' % latlongfile)

except RateLimitExceededError as ex:
  print(ex)
