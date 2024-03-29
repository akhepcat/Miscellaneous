#!/usr/bin/perl
# (c) 2020 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/resolve-hosts.pl
# 
use Socket;
use Getopt::Long;

my $DEBUG=0;

my %HWADDR;
my %IPADDR;
my %HOSTS;
my %LEASE;

sub parse_arp() {
    print "DBG:  parsing arp tables\n" if $DEBUG;

    open(ARPCMD, "arp -an 2>&1 |") || die "Can't run system arp for input";
    while(<ARPCMD>) {
    	chomp;
	next if (m/incomplete/);
	
	if ( m/.*\((.*)\).*at (.*) \[ether.*/ ) {
	    my $ip=$1; my $mac=$2;
	    $HWADDR{$mac}=$ip;
	    $IPADDR{$ip}=$mac;
        }
    }
    close(ARPCMD);
}

sub parse_dhcp() {

    my $inhostdef=0;
    my $hostname;
    my $mac;
    my $ip;

    print "DBG:  parsing dhcp reservations\n" if $DEBUG;

    open(DHCPS, "/etc/dhcp/dhcpd.conf") || print "Can't find /etc/dhcp/dhcpd.conf, skipping DHCP resolution\n";
    while(<DHCPS>) {
	chomp;

	if (m/^(\s*)host\s*(.*) \{/) {
	    $inhostdef=1 ;
	    $hostname=$2;
        }
        if (m/\}/) {
            eval { my $x=inet_ntoa(inet_aton($ip)) };
            next if $@ ne "";
            $inhostdef=0 ;
	    $HWADDR{$mac}=$ip if ( length($HWADDR{$mac}) < 4 );
	    $IPADDR{$ip}=$mac if ( length($IPADDR{$ip}) < 4 );
	    $HOSTS{$ip}=$hostname;
            $mac="";
            $ip="";
            $hostname="";
        }
        next if ($inhostdef != 1);
        	
	if ( m/ethernet\s+([a-f0-9]{1,2}:[a-f0-9]{1,2}:[a-f0-9]{1,2}:[a-f0-9]{1,2}:[a-f0-9]{1,2}:[a-f0-9]{1,2})\s*;/ ) {
	    $mac=$1;
        }
        if (m/fixed-address\s+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/ ) {
            $ip=$1;
        }
    }
    close(DHCPS);
}

sub parse_leases() {
    my $inl=0; my $act=0;
    my $ip; my $mac; my $hn; my $fn;
    my $lf="/var/lib/dhcp/dhcpd.leases";
    
    print "DBG:  parsing dhcp leases\n" if $DEBUG;

    open(LFILE,"$lf") || print "Can't find leasefile db >$lf<, skipping DHCP-leases resolution\n";
    while(<LFILE>) {
        chomp;

        if ($inl == 1) {
            if ($act == 0 && m/binding state active/) {
                print "DBG::leases - binding state active\n" if $DEBUG;
                $act=1;
                next;
            }
            
            if ($act == 1) {
                if (m/hardware ethernet ([a-f0-9:]{17});/i) {
                    $mac=$1;
                    print "DBG::leases - found mac $mac\n" if $DEBUG;
                } elsif (m/ddns-fwd-name = "(.*)";/) {
                    $fn=$1;
                    print "DBG::leases - found ddns-fwd-name $fn\n" if $DEBUG;
                } elsif (m/client-hostname "(.*)";/) {
                    $hn=$1;
                    print "DBG::leases - found client-hostname $fn\n" if $DEBUG;
                }
            }

            if ( m/^}/ ) {
                if ( $act == 1 ) {
                    print "DBG::leases - commiting data\n" if $DEBUG;
        	    $HWADDR{$mac}=$ip if ( length($HWADDR{$mac}) < 4 );
	            $IPADDR{$ip}=$mac if ( length($IPADDR{$ip}) < 4 );
        	    if ($fn) {  $HOSTS{$ip}=$fn; }
        	    if ($hn) {  $HOSTS{$ip}=$hn; }
                }
                $inl=0;
                $ip="";
                $mac="";
                $hn="";
                $fn="";
                $act=0;
            }
        } else { # $inl == 0
            if (m/^lease ([0-9.]{7,15}) \{/ ) {
                $inl=1; $ip=$1;
                print "DBG::leases - found lease entry for $ip\n" if $DEBUG;
            }
        }
    }

    # done parsing the file
    close(LFILE);
}

sub parse_hosts() {
    my $hostname;
    my $ip;

    print "DBG:  parsing hosts file\n" if $DEBUG;

    open(HOSTS, "/etc/hosts") || print "Skipping local resolution, Can't parse /etc/hosts for input\n";
    while(<HOSTS>) {
	chomp;

	next if (m/^(\s*)127\.[0-9]{1,3}/);	# no loopbacks
	next if (m/^(\s*)0\.0\.0\.0/);	# no zero-hosts
	next if (m/^(\s*)[0-9a-f]+:/i); # no IPv6 for now...
	next if (m/^(\s*)\#/); #no comments

	if (m/^(\s*)([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(\s*)([-\.a-z0-9]+)/i) {
	    $ip=$2;
	    $hostname=$4;
	    $HOSTS{$ip} = $hostname if ( length($HOSTS{$ip}) < 2 );
        }
    }
    close(HOSTS);

}

sub dns_hosts() {
    my $hostname;
    my $ip;
    
    print "DBG:  performing DNS lookups\n" if $DEBUG;

    foreach $ip (keys %IPADDR) {
        print "DBG: lookup for $ip:\n" if $DEBUG;
    	$hostname = gethostbyaddr(inet_aton($ip), AF_INET);
    	$HOSTS{$ip} = $hostname if ( ( length($HOSTS{$ip}) < 2 ) && ( length($hostname) > 3) );
    }
}

sub usage {
	print "resolve-hosts.pl\n";
	print "usage:\n";
	print "\t   -e|--everything\trun all parsers, but no ping\n";
	print "\t   -a|--arp_parse\trun the arp parser (default)\n";
	print "\t   -n|--hostname_parse\tparse /etc/hosts\n";
	print "\t   -d|--dhcp_parse\tparse the dhcp config file\n";
	print "\t   -l|--lease_parse\tparse the dhcp leases file\n";
	print "\t   -p|--ping\t\tcheck for host responsiveness\n";
	print "\t-[uh]|--usage|--help\tthis help text\n";
	print @_, "\n";
	exit(1);
}

####################################################################
## MAIN


my(%opt) = (
	everything	=> 0,
        arp_parse	=> 1,
        hostname_parse	=> 0,
        name_lookup	=> 0,
	dhcp_parse	=> 0,
	lease_parse	=> 0,
	ping		=> 0,
        usage		=> 0,
);
Getopt::Long::Configure(qw(ignore_case bundling)); # no difference between -p and -P, and -pq is two valid options

GetOptions( \%opt,
	"everything|e",
        "arp_parse|a",
        "hostname_parse|n",
        "name_lookup|b",
        "dhcp_parse|d",
        "lease_parse|l",
	"ping|p",
        "usage|help|u|h",
) or usage("Invalid option");

usage("") if ($opt{usage});


if ($opt{everything} || $opt{arp_parse}) { parse_arp; }
if ($opt{everything} || $opt{hostname_parse}) { parse_hosts; }
if ($opt{everything} || $opt{name_lookup}) { dns_hosts; }
if ($opt{everything} || $opt{dhcp_parse}) { parse_dhcp; }
if ($opt{everything} || $opt{lease_parse}) { parse_leases; }

my $host;
my $ipaddr;
my $macaddr;
my $state;
my $key;

my @sorted = map inet_ntoa($_), sort map inet_aton($_), keys %IPADDR;

foreach $key (@sorted) {
        next if ( length($key) < 4 );

	$host=$HOSTS{$key};
	$ipaddr=$key;
	$macaddr=$IPADDR{$key};
        $state="unknown";

#        print "DBG: parsing $key\n" if $DEBUG;

        my $PINGC="/bin/ping -n -w 1 -c 1 $key 2>&1|";
	if ( $opt{ping} ) {
#	    print "DBG: cmd='$PINGC'\n" if $DEBUG;
	    open(PINGCMD, $PINGC) || print "Skipping ping due to unknown error\n";
	    while(<PINGCMD>) {
	        chomp;
	        next if (! m/packets transmitted/);
	        print "DBG: ping status: $_\n" if $DEBUG;
	        if (m/1 received/) {
	            $state="alive";
	        } else {
                    $state="dead";
                }
            }
            close(PINGCMD);
        }
        write;

}

exit; 

format STDOUT_TOP =
         Hostname          |      IPv4       |    MAC Address    |  State  
---------------------------|-----------------|-------------------|---------
.

format STDOUT =
@<<<<<<<<<<<<<<<<<<<<<<<<< | @|||||||||||||| | @|||||||||||||||| | @<<<<<<
$host, $ipaddr, $macaddr, $state
.

