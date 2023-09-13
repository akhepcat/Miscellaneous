#!/usr/bin/perl
# (c) 2023 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/oclhcbench2import.pl
# 
# * This takes the oclhcbench2csv output and reformats it so that multiple hosts can be imported into a single spreadsheet or db quickly

use Scalar::Util qw(looks_like_number);

my %device;
my $DEBUG=0;

while (<>) {
	chomp;

	next if (m/^#/);

	if (m/^\*,999999,System Info,\d,(.*);(.*);(.*);(.*);(.*)/) {
	      # *,999999,System Info,0,orange;GNU/Linux;5.10.110-rockchip-rk3588;aarch64;7873636kb
		$host=$1; $os=$2; $kernel=$3; $arch=$4; $mem=$5;

	} elsif (m/^\*,999999,Hashcat Info,0,(.*)/) {
		# *,999999,Hashcat Info,0,v6.2.5
		$hcver=$1;

	} elsif (m/^(\d+),999999,Device Info,0,(.*);(.*);(.*)/) {
		# 1,999999,Device Info,0,pthread-cortex-a55; 2788/5641 MB (1024 MB allocatable); 8MCU
		$dev=$1; $device{$dev}{"cpu"}=$2; $device{$dev}{"cache"}=$3; $device{$dev}{"cores"}=$4;

	} elsif (m/^(\d+),(\d+),(.*),(\d+),(.*)/) {
		# 1,7100,macOS v10.8+ PBKDF2-SHA512 (Iterations: 1023),4175,(195.46ms) @ accel:512 loops:255 thr:1 vec:2
		$dev=$1; $mode=$2; $device{$dev}{$mode}{"desc"}=$3; $device{$dev}{$mode}{"results"}=$4; $device{$dev}{$mode}{"notes"}=$5;
	} else {
		print "DBG: $_\n" if $DEBUG;
	}
}

for $d (keys %device) {
	print "DBG: found device $d\n" if $DEBUG;

	for $m (sort { $a <=> $b } keys %{$device{$dev}}) {
		next if (! looks_like_number($m) );
		print "DBG: found mode $m\n" if $DEBUG;
		$res=$device{$d}{$m}{"results"};
		if ($res > 1000000000) {
			$res=($res / 1000000000);
			$unit="GHs";
		} elsif ($res > 1000000) {
			$res=($res / 1000000);
			$unit="MH/s";
		} elsif ($res > 1000) {
			$res=($res / 1000);
			$unit="kH/s";
		} else {
			$unit="H/s";
		}
		
		printf("%d,%s,%s,%s,%s,,%.1f %s,%s\n",
			$m, $device{$d}{$m}{"desc"}, $host, "CPU", $device{$d}{"cpu"}, $res, $unit, $device{$d}{$m}{"notes"});
	}
}
