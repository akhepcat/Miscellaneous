#!/usr/bin/perl -w

use strict;
use Benchmark;
use Socket;

use vars qw/@ip_strings/;

# these are all made up I hope

@ip_strings = qw(192.168.1.1. 192.168.1.2 152.2.100.2 204.165.43.1 1.2.3.4 152.2.1.23 112.145.165.205 2.2.2.2. 4.5.6.7 8.9.10.12 2.4.6.8 10.12.14.16);

timethese (100000, {

## I leave aton-ntoa 'disabled' because it's > 500x worse than the other sort methods.
##
# 130 wallclock secs (119.86 usr +  5.10 sys = 124.96 CPU) @ 80.03/s (n=10000)
#        'aton-ntoa',
#        q{
#                my @packed_ips;
#                @packed_ips = map inet_ntoa($_), sort map inet_aton($_), @ip_strings;
#        },


# 10 wallclock secs ( 9.36 usr +  0.00 sys =  9.36 CPU) @ 10683.76/s (n=100000)
        'regex-cmp',
        q|
                my @packed_ips;
                @packed_ips = sort { pack('C4' => $a =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) cmp pack('C4' => $b =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/)  } @ip_strings;
	|,

#  3 wallclock secs ( 3.07 usr +  0.00 sys =  3.07 CPU) @ 32573.29/s (n=100000)
        'regex-map',
        q{
                my @packed_ips;
                @packed_ips = map  substr($_, 4) =>
                  sort
                    map  pack('C4' =>
                        /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
                              . $_ => @ip_strings;
        },

#  2 wallclock secs ( 2.11 usr +  0.00 sys =  2.11 CPU) @ 47393.36/s (n=100000)
        'split-map',
        q{
                my @packed_ips;
                @packed_ips = map  substr($_, 4) =>
                  sort
                    map  pack('C4' =>
                        split /\./, $_)
                              . $_ => @ip_strings;
        },
  }
);
