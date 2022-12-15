#!/usr/bin/perl
# (c) 2022 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/dshield_nft_blocklist.pl
# 

use Net::Netmask;
use JSON::Parse 'parse_json';

# This is the one you always want to customize;  some RFC-1918 examples, AWS and Google also... 
my @never_block=("192.168.0.0/22", "172.16.130.0/23", "192.168.13.0/24", "54.240.0.0/18", "209.85.128.0/17" );

# This should *probably* be customized, but this gets most of the bogons from encroaching through your external interface; Classic RFC-1918 is .. not blocked by default!
my @always_block=("0.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/3" );
my @cidrs;

open(NFT, "/sbin/nft -s -nnn list set netdev filter blocklist_v4 -j |" ) || die "can't open nft to import blocklist_v4 filter";
while(<NFT>) {
    $json.="$_";
}

# Ugh, working our way through the json output is... horrible.
my $parsed=parse_json($json);
my @arr1 = @{$parsed->{nftables}};
my @arr2 = @{$arr1[1]->{set}->{elem}};

my $max = $#arr2;

for ( $i=0; $i < $max +1; $i++) {
    my %prefix;
    my @range;
    my $cidr;

    my %hash1 = %{@arr2[$i]};

    if ( defined($hash1{prefix}) ) {
        %prefix = %{$hash1{prefix}};
        $cidr=$prefix{addr} . "/" . $prefix{len};
        
    } elsif (defined($hash1{range})) {
    
	my @v1 = $hash1{range};
	my @range = @{$v1[0]};

	$cidr = Net::Netmask->safe_new($range[0] . "-" . $range[1])->desc();

    } else {
        next;
    }

    next if (!defined($cidr));

    if (! grep (/^$cidr/, @always_block) ) {
        push @cidrs, $cidr;
    }
}

my $rcidrs = join(',', @cidrs);
if (scalar @cidrs >=1 ) {
    system(qq|/sbin/nft delete element netdev filter blocklist_v4 "{ $rcidrs }"\n|);
}

@cidrs=();

open(RPT, qq!curl -silent https://www.dshield.org/block.txt | grep -E '^[0-9]+' | awk '{print \$1 "/" \$3}'| !) || die "can't read cidrs from dshield report";
while (<RPT>) {
    chomp;
    push @cidrs, $_;
}

close(RPT);
my @bcidrs=();

foreach $cidr (@cidrs) {
    my $block = 1;
    my $nt = Net::Netmask->safe_new($cidr);

    if (!defined($nt) ) {
        print "couldn't build net::netmask object against $cidr\n";
        next;
    }

    foreach $permit (@never_block)
    {
        my $test = Net::Netmask->safe_new($permit);
        if ( $nt->contains($test) eq 1 or $test->contains($nt) eq 1 ) {
            $block = 0;
        }
    }

    if ($block eq 1) {
        push @bcidrs, $cidr;
    }
}

if (scalar @bcidrs >= 1) {
    my $bcd = join(',', @bcidrs);
    system(qq|/sbin/nft add element netdev filter blocklist_v4 "{ $bcd }"\n|);
}
