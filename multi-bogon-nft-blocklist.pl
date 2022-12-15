#!/usr/bin/perl
# (c) 2022 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/multi-bogon-nft-blocklist.pl
# 
use Net::Netmask;
use JSON::Parse 'parse_json';
use Data::Dumper;
use Scalar::Util qw(reftype);

##############################################
## Configuration data
##############################################

# Which sources should be enabled?  at least one, or this breaks...
my $DSHIELD=1;
my $CYMRU=1;
my $SHDROP=1;
my $SHEDROP=1;

my @always_block=("0.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/3" );
# localhosts, aws
my @never_block=("192.168.0.0/22", "54.240.0.0/18" );

my @cidrs; 

my $DEBUG=0;	# 0 for production, 1 will echo the commands to be run

##############################################
## Program follows
##############################################

my $sysconf="/etc/default/multibl.conf";	# by default...
if (open(CONF, "<$sysconf")) {
    my @t; my $var;
    while(<CONF>) {
        chomp;
        my $i;

        if (m/^[[:space:]]*([[:alpha:]]+)=(.*)/) {
            $var=$1; $_=$2;
            s/\s+#.*//; s/"//; # remove comments and floating quotes

            print "DBG: configfile discovered var '$var' with contents " . $_ . "\n" if $DEBUG;
            if ($var eq "DSHIELD") {
                $DSHIELD=$_;
            } elsif ( $var eq "CYMRU" ) {
                $CYMRU=$_;
            } elsif ( $var eq "SHDROP") {
                $SHDROP=$_;
            } elsif ( $var eq "SHEDROP") {
                $SHEDROP=$_;
            } elsif ( $var eq "DEBUG") {
                $DEBUG=$_;
            } else {
                foreach $i (split /,/, $_) {
                    push @t, $i;
                }
                if (scalar @t >=1 ) {
                    if ($var eq "always_block") {
                        push(@always_block,@t);
                    } elsif ($var eq "user_block") {
                        push(@always_block,@t);
                    } elsif ($var eq "never_block") {
                        push(@never_block,@t);
                    }
                }
            }
        }
    }
    close(CONF);
} else {
    print "can't open $sysconf, using hard-coded defaults\n";
}



if ($DSHIELD + $CYMRU + $SHDROP + $SHEDROP < 1) {
    print "ERROR: No blocklist sources configured\n";
    exit(1);
}

open(NFT, "nft -s -nnn list set netdev filter blocklist_v4 -j |" ) || die "can't open nft to import blocklist_v4 filter";
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
    my $c;
    my $lp=0;

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
    foreach my $abn (@always_block) {
        my $ab = Net::Netmask->safe_new($abn);
        $c = Net::Netmask->safe_new($cidr);

        if ( ($ab->contains($c) eq 0) and ($c->contains($ab) eq 0) ) {
            $lp++;
        }
    }
    if ( $lp gt 0 ) {
        print "removing $cidr from blocklist\n" if $DEBUG;
        push @cidrs, $c;
    }
}

my @tcidrs = cidrs2cidrs(@cidrs);  #collapse the IP subnets to their smallest functions 
@cidrs=();
foreach my $tc (@tcidrs) {	# convert back to text
    push(@cidrs, $tc->desc() );
}

my $rcidrs = join(',', @cidrs);
if (scalar @cidrs >=1 ) {
    if ($DEBUG == 1) {
        print qq|/sbin/nft delete element netdev filter blocklist_v4 "{ $rcidrs }"\n|;
    } else {
        system(qq|/sbin/nft delete element netdev filter blocklist_v4 "{ $rcidrs }"\n|);
    }
}

# From here it will be an array of Net::Netmasks
@cidrs=();

if ($DSHIELD == 1 ) {
    # Top-20 attacking /24's over the last three days; updates every hour
    open(RPT, qq!curl -silent https://feeds.dshield.org/block.txt | grep -E '^[0-9]+' | awk '{print \$1 "/" \$3}'| !) || die "can't read cidrs from dshield report";
    while (<RPT>) {
        chomp;
        if (m/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2})/) {
            push(@cidrs, Net::Netmask->safe_new($1) );
        }
    }
    close(RPT);
}
if ($CYMRU == 1 ) {
    # Textual Full bogon list, updates every four hours
    open(RPT, qq!curl -silent https://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt | grep -E '^[0-9]+'| !) || die "can't read cidrs from cymru fullbogon report";
    while (<RPT>) {
        chomp;
        if (m/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2})/) {
            push(@cidrs, Net::Netmask->safe_new($1) );
        }
    }
    close(RPT);
}

if ($SHDROP == 1 ) {
    # SpamHaus Don't Route or Peer list, updates once per day
    open(RPT, qq!curl -silent https://www.spamhaus.org/drop/drop.txt | grep -E '^[0-9]+' | cut -f1 -d";" | !) || die "can't read cidrs from cymru fullbogon report";
    while (<RPT>) {
        chomp;
        if (m/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2})/) {
            push(@cidrs, Net::Netmask->safe_new($1) );
        }
    }
    close(RPT);
}

if ($SHEDROP == 1 ) {
    # SpamHaus Extended Don't Route or Peer list, updates once per day
    open(RPT, qq!curl -silent https://www.spamhaus.org/drop/edrop.txt | grep -E '^[0-9]+' | cut -f1 -d";" | !) || die "can't read cidrs from cymru fullbogon report";
    while (<RPT>) {
        chomp;
        if (m/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2})/) {
            push(@cidrs, Net::Netmask->safe_new($1) );
        }
    }
    close(RPT);
}


my @bcidrs=();
@cidrs = cidrs2cidrs(@cidrs);  #collapse the IP subnets to their smallest functions 

foreach $cidr (@cidrs) {
    my $block = 1;

    foreach $permit (@never_block)
    {
        my $test = Net::Netmask->safe_new($permit);
        if ( $cidr->contains($test) eq 1 or $test->contains($cidr) eq 1 ) {
            $block = 0;
        }
    }

    if ($block eq 1) {
        # print "Adding block for $cidr\n";
        push @bcidrs, $cidr->desc();
    }
}

if (scalar @bcidrs >= 1) {
    my $bcd = join(',', @bcidrs);
    if ($DEBUG == 1) {
        print qq|/sbin/nft add element netdev filter blocklist_v4 "{ $bcd }"\n|;
    } else {
        system(qq|/sbin/nft add element netdev filter blocklist_v4 "{ $bcd }"\n|);
    }
}
