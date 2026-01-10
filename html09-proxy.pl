#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use Getopt::Long;

my $appname = $0;
$appname =~ s|.*/||;

# defaults
my $BindIP = '127.0.0.1';
my $Port = 8080;
my $CType = 'text/html; charset=utf-8';
my $Debug = 0;

sub dbg {
    my ($lvl, $msg) = @_;
    print "[D$lvl] $msg\n" if $Debug >= $lvl;
}

sub usage {
    print "$appname:\t\t (c)2025 - github/akhepcat\n";
    print "\n";
    print "\tCorrects and upscales pre-http/1.0 servers to http/1.0 and http/1.1 compliant browsers\n";
    print "\t\t* adds missing content-type headers\n";
    print "\t\t* adds missing content-length headers\n";
    print "\t\t* adds missing connection headers\n";
    print "\t\t* correctly handles get/post methods\n";
    print "\t\t* correctly handles keep-alives\n";
    print "\tLLM usage disclamier:\n";
    print "\t\t* content-compliance upscaling code corrected by Gemini/ChatGPT\n";
    print "\t\t* conversion to eliminate non-base modules by ChatGPT\n\n";
    print "usage:\n";
    print "\t-b|--bind [addr]\tbind to specific IP (default: $BindIP)\n";
    print "\t-p|--port [port]\tTCP port to listen on (default: $Port)\n";
    print "\t-c|--ctype [string]\tforce content type when not provided (default: $CType)\n";
    print "\t-d|--debug\t\teach '-d' increases debug logging level (1-6)\n";
    print "\t-[uh]|--usage|--help\tthis help text\n";
    print @_, "\n";
    exit(0);
}

my %opt = (
    bind => $BindIP,
    port => $Port,
    ctype => $CType,
    debug => 0,
    help => 0,
    usage => 0,
);

Getopt::Long::Configure(qw(ignore_case bundling));

GetOptions(
    \%opt,
    "bind|b=s",
    "port|p=i",
    "ctype|c=s",
    "debug|d+",
    "usage|help|u|h",
) or usage("Invalid option");

$BindIP = $opt{bind};
$Port = $opt{port};
$CType = $opt{ctype};
$Debug = $opt{debug};

usage("") if ($opt{help} || $opt{usage});

my $server = IO::Socket::INET->new(
    LocalAddr => $BindIP,
    LocalPort => $Port,
    Listen => 10,
    Reuse => 1,
) or die "Cannot bind to $BindIP:$Port: $!\n";

dbg(1, "$appname (HTTP/1.1-aware) listening on $BindIP:$Port");

while (my $cli = $server->accept) {
    my $pid = fork();
    if (!defined $pid) {
        warn "fork failed: $!";
        next;
    }
    if ($pid == 0) {    # child
        $server->close;
        $cli->autoflush(1);
        my $peer = $cli->peerhost . ":" . $cli->peerport;
        dbg(2, "accepted connection from $peer");

        my $reqline = <$cli>;
        unless (defined $reqline) { dbg(2, "client closed connection"); exit 0; }
        
        chomp $reqline;
        dbg(4, "REQ: $reqline");

        my %hdr;
        while (my $h = <$cli>) {
            last if $h =~ /^\r?\n$/;
            chomp $h;
            my ($k, $v) = split /:\s*/, $h, 2;
            $hdr{lc $k} = $v;
            dbg(5, " req-hdr: $h");
        }
        
        my $req_body = '';
        if (exists $hdr{'content-length'} && $hdr{'content-length'} > 0) {
            my $length = $hdr{'content-length'};
            my $bytes_read = 0;
            while ($bytes_read < $length) {
                my $buf;
                my $n = $cli->read($buf, $length - $bytes_read);
                last unless defined $n && $n > 0;
                $req_body .= $buf;
                $bytes_read += $n;
            }
            dbg(5, " read req-body ($bytes_read bytes)");
        }
        
        my ($method, $url, $proto) = split ' ', $reqline;
        $proto ||= "HTTP/1.0";

        if (uc $method eq 'CONNECT') {
            my ($host, $port) = split /:/, $url;
            $port ||= 443;
            my $remote = IO::Socket::INET->new(
                PeerAddr => $host,
                PeerPort => $port,
            );
            if ($remote) {
                print $cli "HTTP/1.0 200 Connection Established\r\n\r\n";
                dbg(3, "CONNECT tunnel to $host:$port established");
                my $rin = '';
                vec($rin, fileno($cli), 1) = 1;
                vec($rin, fileno($remote), 1) = 1;
                while (1) {
                    my $rout = $rin;
                    select($rout, undef, undef, undef);
                    if (vec($rout, fileno($cli), 1)) {
                        my $data;
                        my $n = sysread($cli, $data, 8192);
                        last unless $n;
                        syswrite($remote, $data);
                    }
                    if (vec($rout, fileno($remote), 1)) {
                        my $data;
                        my $n = sysread($remote, $data, 8192);
                        last unless $n;
                        syswrite($cli, $data);
                    }
                }
                close $remote;
            } else {
                print $cli "HTTP/1.0 502 Bad Gateway\r\n\r\n";
            }
            close $cli;
            dbg(2, "connection closed for $peer");
            exit 0;
        }

        my ($host, $port, $path);
        
        # Dynamically determine the host and port from the URL or headers
        if ($url =~ m{^http://([^/:]+)(?::(\d+))?(.*)$}) {
            $host = $1;
            $port = $2 || 80;
            $path = $3 || "/";
        } elsif (exists $hdr{'host'}) {
            ($host, $port) = split /:/, $hdr{'host'};
            $port ||= 80;
            $path = $url;
        } else {
            print $cli "HTTP/1.0 400 Bad Request\r\n\r\n";
            close $cli;
            dbg(2, "connection closed for $peer");
            exit 0;
        }

        my $remote = IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
        );
        unless ($remote) {
            print $cli "HTTP/1.0 502 Bad Gateway\r\n\r\n";
            close $cli;
            dbg(2, "connection closed for $peer");
            exit 0;
        }

        print $remote "$method $path $proto\r\n";
        foreach my $k (keys %hdr) {
            next if $k eq 'proxy-connection';
            print $remote ucfirst($k) . ": $hdr{$k}\r\n";
        }
        print $remote "\r\n";

        if (length $req_body > 0) {
            print $remote $req_body;
        }
 
        my $response_from_server = '';
        my $first_line = <$remote>;
        unless (defined $first_line) {
            dbg(3, "Remote server closed connection unexpectedly");
            close $remote;
            close $cli;
            dbg(2, "connection closed for $peer");
            exit 0;
        }
        $response_from_server .= $first_line;

        my $needs_close = 0;
        my %resp_hdr;
        my $is_msie7 = exists $hdr{'user-agent'} && $hdr{'user-agent'} =~ /MSIE 7\.0/;

        if ($first_line =~ m{^HTTP/\d\.\d\s+\d+}) {
            dbg(4, "RESP status: $first_line");
            
            my $header_end = 0;
            while (my $h = <$remote>) {
                $response_from_server .= $h;
                if ($h =~ /^\r?\n$/) {
                    $header_end = 1;
                    last;
                }
                chomp $h;
                my ($k, $v) = split /:\s*/, $h, 2;
                $resp_hdr{lc $k} = $v;
                dbg(6, " resp-hdr: $h");
            }

            if ($header_end) {
                while (my $buf = <$remote>) {
                    $response_from_server .= $buf;
                }
            }

            my ($head, $body) = split /^\r?\n/s, $response_from_server, 2;
            my $new_headers = "$head\r\n";
            $body ||= '';

            my $has_size_info = exists $resp_hdr{'content-length'} || exists $resp_hdr{'transfer-encoding'};
            
            if (!exists $resp_hdr{'content-type'}) {
                dbg(3, "Injected missing Content-Type");
                $new_headers .= "Content-Type: $CType\r\n";
                $needs_close = 1;
            }

            unless ($has_size_info) {
                my $body_len = length $body;
                dbg(3, "Injected missing Content-Length: $body_len");
                $new_headers .= "Content-Length: $body_len\r\n";
                $needs_close = 1;
            }

            if (exists $resp_hdr{'connection'} && $resp_hdr{'connection'} =~ /close/i) {
                dbg(3, "Forwarding Connection: close as per server header");
                $new_headers .= "Connection: close\r\n";
            }
            else {
                dbg(3, "Injected Connection: Keep-Alive to the browser");
                $new_headers .= "Connection: Keep-Alive\r\n";
            }

            $new_headers .= "\r\n";
            
            print $cli $new_headers;
            print $cli $body;
        }
        else {
            dbg(3, "Headerless response detected, synthesizing HTTP/1.0 200 OK");
            
            while (my $buf = <$remote>) {
                $response_from_server .= $buf;
            }
            
            my $body_len = length $response_from_server;
            
            print $cli "HTTP/1.0 200 OK\r\n";
            print $cli "Content-Type: $CType\r\n";
            print $cli "Content-Length: $body_len\r\n";
            
            if ($is_msie7) {
                dbg(3, "MSIE 7.0 detected, omitting Connection header");
            } else {
                dbg(3, "Synthesizing Connection: Keep-Alive");
                print $cli "Connection: Keep-Alive\r\n";
            }
            
            print $cli "\r\n";
            print $cli $response_from_server;
        }

        close $remote;
        close $cli;
        dbg(2, "connection closed for $peer");
        exit 0;

    } else {
        close $cli;
    }
}

