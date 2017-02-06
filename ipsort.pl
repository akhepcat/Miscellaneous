#!/usr/bin/perl
use Socket;

my @in;
my $DEBUG=0;

while(<>) {
   chop;
   next if ($_ == "");
   print "DBG3: in=($_)\n" if $DEBUG >= 3;

   if (m/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}).*/) {
     print "DBG2: ip_found($1)\n" if $DEBUG >= 2;
     eval { my $x=inet_ntoa(inet_aton($1)) };
     next if $@ ne "";
     print "DBG1: ip_push($1)\n" if $DEBUG >= 1;
     push @in, $1;
   }
}

print "DBG5: unsorted IPs (@in)\n" if $DEBUG >= 5;

my @sorted =  map  substr($_, 4) => sort map  pack('C4' => split /\./, $_)  . $_ => @in;

foreach $ip (@sorted) {
  print "$ip\n";
}

