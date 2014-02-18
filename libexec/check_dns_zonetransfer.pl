#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Std;
use Carp qw(croak carp);
use Data::Dumper;
use Net::DNS;	#DEPENDENCY!
use Try::Tiny;  #DEPENDENCY!


use lib "/usr/local/nagios/libexec"; # Path util.pm !!
use utils qw ($TIMEOUT %ERRORS);
#my $TIMEOUT=15; my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my %ERRORS_R=(0 => 'OK',1 =>'WARNING',2 =>'CRITICAL',3 => 'UNKNOWN', 4 => 'DEPENDENT');

my $usage= qq ~
usage: $0 -Z <Zonename1,...> [-N <Path to named.conf>  -w <warning thresholds in Minutes> -c <critical thresholds in Minutes> -T <Timeout,Timeout> -d ] | -h 

\t-N:\t Path to named.conf Default: '/etc/bind/named.conf'
\t-Z:\t comma seperated list of Zones you want to monitor
\t-w:\t Default: 2880,20 
\t-c:\t Default: 1440,30
\t\t Threshold in the following format: <X,Y>  
\t\t <Minutes until Zone times out,How long can the master have a higher serial (in Minutes)>
\t-T:\t script timeout and connection timeout for SOA request on master in seconds. Default: <from util.pm,5> seconds
\t-d:\t additional debug output


~;

my %opt=();
getopts('h?N:Z:T:w:c:d',\%opt)or (print $usage and exit(2));
(print $usage and exit(2)) if $opt{'h'} or $opt{'?'}; 
(print $usage and exit(2)) if !defined $opt{'Z'};
$opt{'N'} = "/etc/bind/named.conf" 	if !defined $opt{'N'} ;
$opt{'w'} = "2880,20" 				if !defined $opt{'w'} ;
$opt{'c'} = "1440,30" 				if !defined $opt{'c'} ;
$opt{'T'} = $TIMEOUT.",5" 			if !defined $opt{'T'};
(print $usage and exit(2)) 			if $ARGV[0];


# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	print "UNKNOWN - Plugin Timed out\n";
	exit $ERRORS{"UNKNOWN"};
};
alarm((split /,/, $opt{'T'})[0]);



sub main{
	# define a clear starting point:
	my $TEMPBASENAME="/tmp/check_dns_zonetransfer.TMP.";
	my @output=(); my @perfout=(); my $ret_code=0;
	my %Zones;
	
	print "\ntrying to read Zones (". $opt{'Z'} .') from named.conf ('. $opt{'N'} .")\n" if $opt{'d'};
	try {
		%Zones =_readNamedConf($opt{'N'},$opt{'Z'});	
	}catch{
		print "@_";
		exit(2);
	};
	print "...success. Got this from config:\n" if $opt{'d'};
	print Dumper(\%Zones) if $opt{'d'};
	
	try {
		chdir $Zones{'directory'} or croak "Can not change to directory $Zones{'directory'}: $!";
		#delete $Zones{'directory'} or croak "Can not delete old tempfile\n: $!";
	}catch{
		print "@_\n";
		exit(2);
	};
	
	
	# check every zone
	for my $zoneName ( keys %Zones) {
		my $SOA_S; my $SOA_M=''; 
		print "prozessing zone: $zoneName...\n" if $opt{'d'};
		print "  get SOA Record from localhost\n" if $opt{'d'};
		try{
			$SOA_S = _qrsoa('127.0.0.1',$zoneName,(split /,/, $opt{'T'})[1]);
		}catch{
			print "@_";
			exit(2);	
		};
		print "    Serial is: ". $SOA_S->serial ."\n" if $opt{'d'};
		
		MASTER: while (my $master = shift @{$Zones{$zoneName}{'masters'}} ) {
			print "  querying SOA Record from Master: $master\n" if $opt{'d'};
			#get zonedata from Master and localhost or die
			try{
				$SOA_M = _qrsoa($master,$zoneName,(split /,/, $opt{'T'})[1]);
			}catch{
				print "    ERROR. Could not get SOA Record. Probing next Master\n" if $opt{'d'};
				next MASTER;	
			};
			
			print "    Serial is: ". $SOA_M->serial ."\n" if $opt{'d'};
			#compare the serials
			print "    doing tests...\n" if $opt{'d'};
			if ($SOA_M->serial == $SOA_S->serial) {	
				
				unlink $TEMPBASENAME . $zoneName . $master if -f $TEMPBASENAME . $zoneName . $master;
				#compare file mtime and Zone lifetime (SOA->expire)
				my $delta= ((stat($Zones{$zoneName}{'file'}))[9] + $SOA_S->expire) - time;
				
				if( $delta < ((split /,/,$opt{'c'})[0]*60) ){
					push @output, $zoneName ." expires in ". sprintf( "%.0f", (($delta)/3600)) ."h. ;";
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, (($delta)/60), (split /,/,$opt{'w'})[0], (split /,/,$opt{'c'})[0]);
					$ret_code = 2;
				}elsif( $delta < ((split /,/,$opt{'w'})[0]*60) ){ 
					push @output, $zoneName ." expires in ". sprintf( "%.0f", (($delta)/3600)) ."h. ;";
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, (($delta)/60), (split /,/,$opt{'w'})[0], (split /,/,$opt{'c'})[0]);
					$ret_code = 1 if $ret_code<2;
				}else{ 
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, (($delta)/60), (split /,/,$opt{'w'})[0], (split /,/,$opt{'c'})[0]);
				}
				print "      Serials match, zone expires in ". sprintf( "%.0f", (($delta)/3600)) ."hours.\n" if $opt{'d'};
				
			}elsif ($SOA_M->serial > $SOA_S->serial){
				
				_touch($TEMPBASENAME . $zoneName . $master) if ! -f $TEMPBASENAME . $zoneName . $master;
				my $delta = time - (stat($TEMPBASENAME . $zoneName . $master))[9];
				
				if( $delta > ((split /,/,$opt{'c'})[1]*60) ) {
					push @output, $zoneName ." out of Sync for ". sprintf("%.0f", ($delta/60)) ."min. ;";
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, -1*(($delta)/60), -1*(split /,/,$opt{'w'})[1], -1*(split /,/,$opt{'c'})[1]); 
					$ret_code = 2;
				}elsif( $delta > ((split /,/,$opt{'w'})[1]*60) ) {
					push @output, $zoneName ." out of Sync for ". sprintf( "%.0f", ($delta/60)) ."min. ;";
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, -1*(($delta)/60), -1*(split /,/,$opt{'w'})[1], -1*(split /,/,$opt{'c'})[1]); 
					$ret_code = 1 if $ret_code<2;
				} else { 
					push @perfout, sprintf( "'%s'=%.0f;%.0f;%.0f;;", $zoneName, -1*(($delta)/60), -1*(split /,/,$opt{'w'})[1], -1*(split /,/,$opt{'c'})[1]);
				}
				print "      Serial on Master is higher since ". sprintf( "%.0f", ($delta/60)) ."min.\n" if $opt{'d'};
				
			}else{
				print "      Serial on Master (". $master .") is lower then the local copy. testing next master...\n" if $opt{'d'};
				next MASTER if @{$Zones{$zoneName}{'masters'}} >0;
				push @output, "Our local Serial is higher then on all Master Server for Zone: ". $zoneName ." ;";
				push @perfout, "'$zoneName'=0;;;;";
				$ret_code = 2;
			}
			last;
		}
		if ( !$SOA_M ) {
			push @output, "Could not reach any Master for zone: $zoneName ;";
			$ret_code= 2;
		}
	}
	print $ERRORS_R{$ret_code} ." - ". join (' ', @output) ." |". (join " ", @perfout) ."\n";
	exit($ret_code);
}

sub _touch {
	my $FILENAME = shift;
	my $now = time;
	utime($now,$now,$FILENAME)|| open(my $TMP,">>", $FILENAME)|| 
		carp "Couldn't touch $FILENAME:$!\n";
	close $TMP;
}

sub _qrsoa {
	my $host = shift;
	my $zone = shift;
	my $timeout = shift;
	my $res   = Net::DNS::Resolver->new(nameservers => [$host], tcp_timeout => $timeout, udp_timeout => $timeout );
	my $query = $res->query($zone, "SOA");
	croak ("something went wrong with the Request on $host") if !$query;
	croak ("SOA query failed") if !defined($query) || ($query->header->ancount <= 0);
	croak ("Type mismatch: ". ($query->answer)[0]->type) if ($query->answer)[0]->type ne "SOA";
	
	return ($query->answer)[0];
}

sub _readNamedConf {
	my ($file, $zones)=@_;
	my @ZonesWanted= split /,/, $zones;
	my $in=0; my %item; my %ret;
	
	# read named.conf file into array
	open my $fh, "<", $file or croak "cant open file $file: $!";
	my @namedConf=<$fh>;
	close $fh;
	
	while (my $line = shift @namedConf ) {
		# get rid of comments and leading whitespaces
		$line =~ s/\/\/.*//;
		$line =~ s/^\s*//;
		
		if($line =~ /^zone\s+"(.*?)"/i){
			$in=1;
			$item{'name'}=$1;
		}elsif ( $line =~ /}/ && $in == 1 ) {
			$in=0;
			if ( $item{'type'} ne 'slave' or !grep { $item{'name'} eq $_ } @ZonesWanted) {
				%item = ();
				next;
			}
			croak "Could not find masters for Zone $item{'name'}" if scalar @{$item{'masters'}} == 0;
			croak "Could not find zonefile entry for Zone $item{'name'}" if ! $item{'file'};	
			
			$ret{$item{'name'}}={
				'file' => $item{'file'},
				'masters' => $item{'masters'},
			};
			@ZonesWanted= grep {$_ ne $item{'name'} } @ZonesWanted;
			%item = ();
		}elsif ( $in ) {
			# get filename
			$item{'file'}= $1 if $line =~ /file\s+"(.*?)"/i; 
			# get type 
			$item{'type'}= $1 if $line =~ /type\s+(\w+)/i;
			# get masters
			if ( $line =~ /masters/i ) {
				$item{'masters'}=();
				my $innerLine = shift @namedConf;
				while ($innerLine !~ /}/) {
					$innerLine =~ /(\d+\.\d+\.\d+\.\d+)/;
					push @{$item{'masters'}}, $1;
					$innerLine = shift @namedConf;
				}
			# get rid of all other statement that open and close parantheses like allow-transfer{}, also-notify{}
			}elsif ( $line =~ /{/ ){
				my $innerLine = shift @namedConf;
				while ($innerLine !~ /}/) {
					$innerLine = shift @namedConf;
				}
			}
			# thats all we care about....so far
		}
		if ( $line =~ /directory\s+"(.*?)"/i ) {
			$ret{'directory'}=$1;
		}
	}
	croak "Could not find Zone(s): ". join(', ', @ZonesWanted) if @ZonesWanted>0 ;
	return %ret;
}

main();
exit(3);
