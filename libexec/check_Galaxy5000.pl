#!/usr/bin/env perl
#http://soft.apc.com/manual/network/en/xml_ag/ag_mib.htm

use strict;
use warnings;
use Getopt::Std;
use Net::SNMP;
use Switch;

use lib "/usr/local/nagios/libexec"; # Path to util.pm !!
use utils qw ($TIMEOUT %ERRORS);
#my $TIMEOUT=10; my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4); 

my %oids=(	'SerialNumber' => '1.3.6.1.4.1.705.1.1.7.0',
			'Firmware' => '.1.3.6.1.4.1.705.1.1.4.0',
			'BatteryTemperature' => '.1.3.6.1.4.1.705.1.5.7.0',
			'OutputOnBattery' => '1.3.6.1.4.1.705.1.7.3.0',
			'BatteryRemainingTime' => '1.3.6.1.4.1.705.1.5.1.0',
			'BatteryLowBattery' => '1.3.6.1.4.1.705.1.5.14.0',
			'BatteryLevel' => '1.3.6.1.4.1.705.1.5.2.0',
			'BatteryFaultBattery' => '1.3.6.1.4.1.705.1.5.9.0',
			'BatteryReplacement' => '1.3.6.1.4.1.705.1.5.11.0',
			'BatteryChargerFault' => '1.3.6.1.4.1.705.1.5.15.0',
			'OutputOnByPass' => '1.3.6.1.4.1.705.1.7.4.0',
		);

my $usage= qq ~
usage: $0 -H <hostname> -C <Community> -M <mode> [ -w <Warn> -c <Crit> -T <Timeout> -] | -h 

\t-H\t IP of Host
\t-C\t optional: snmp Comunity
\t\t default: public
\t-w|-c\t optional: Warning and Critical Threshold
\t\t default(on temperature values): warn:31°C and crit:37°C
\t\t default(on time values): warn:3600s and crit:2400s
\t\t default(on % values): warn:50% and crit:30%
\t-M\t Mode:
\t\t <SerialNumber>
\t\t <Firmware>
\t\t <BatteryTemperature>
\t\t <OutputOnBattery>
\t\t <BatteryRemainingTime>
\t\t <BatteryLowBattery>
\t\t <BatteryLevel>
\t\t <BatteryFaultBattery>
\t\t <BatteryReplacement>
\t\t <BatteryChargerFault>
\t\t <OutputOnByPass>
\t-T\t optional: Timeout in seconds
\t\t defaults: 15 seconds
\t-d\t optional: debug output on stderr 
\t-h\t prints this helpmessage

~;

my %opt=();
getopts('h?T:H:C:w:c:M:d',\%opt)or (print $usage and exit(2));
(print $usage and exit(2)) if $opt{'h'} or $opt{'?'}; 
(print $usage and exit(2)) if !defined $opt{'H'} || $opt{'H'}!~/\d+\.\d+\.\d+\.\d+/;
$opt{'T'}=$opt{'T'} || $TIMEOUT;
$opt{'C'}=$opt{'C'} || 'public';
if(!$opt{'w'} && $opt{'M'} eq 'BatteryTemperature'){$opt{'w'}=31;}
if(!$opt{'w'} && $opt{'M'} eq 'BatteryRemainingTime'){$opt{'w'}=3600;}
if(!$opt{'w'} && $opt{'M'} eq 'BatteryLevel'){$opt{'w'}=50;}
if(!$opt{'c'} && $opt{'M'} eq 'BatteryTemperature'){$opt{'c'}=37;}
if(!$opt{'c'} && $opt{'M'} eq 'BatteryRemainingTime'){$opt{'c'}=2400;}
if(!$opt{'c'} && $opt{'M'} eq 'BatteryLevel'){$opt{'c'}=30;}
(print $usage and exit(2)) if !defined $opt{'M'} || !grep {/^$opt{'M'}$/} keys %oids;
(print $usage and exit(3)) if $ARGV[0];


# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
        print "UNKNOWN - Plugin Timed out\n";
        exit $ERRORS{"UNKNOWN"};
};
alarm($opt{'T'});

sub _create_snmp_session {
	my ($server, $comm) = @_;
	my $version = 1; #0=v1; 1=v2c; 2=v3
	my ($sess, $err) = Net::SNMP->session( -hostname => $server, -version => $version, -community => $comm);
	if (!defined($sess)) {
		print "ERROR - Can't create SNMP session to $server\n\t-> $err";
		exit(2);
	}
	return $sess;
}

my $snmp=_create_snmp_session($opt{'H'},$opt{'C'});

switch ($opt{'M'}){
	case "SerialNumber"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'SerialNumber'}]);
		if ( $result ) {
			print "OK - Serial Number is ". $result->{$oids{'SerialNumber'}} ."\n";
			exit($ERRORS{'OK'});
		} 
		else { 
			print "ERROR - Could not fetch Serial Number.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "Firmware"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'Firmware'}]);
		if ( $result ) {
			print "OK - Firmware Version is ". $result->{$oids{'Firmware'}} ."\n";
			exit($ERRORS{'OK'});
		} 
		else { 
			print "ERROR - Could not fetch Firmware Version.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryTemperature" {
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryTemperature'}]);
		if ( $result ) {
			(print "OK - Battery Temperature is ". $result->{$oids{'BatteryTemperature'}} ."C | BatteryTemperature=". 
			      $result->{$oids{'BatteryTemperature'}} .";". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'OK'})) if $result->{$oids{'BatteryTemperature'}} < $opt{'w'};
			(print "WARNING - Battery Temperature is ". $result->{$oids{'BatteryTemperature'}} ."C | BatteryTemperature=". 
			      $result->{$oids{'BatteryTemperature'}} .";". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'WARNING'})) if $result->{$oids{'BatteryTemperature'}} < $opt{'c'};
			print "CRITICAL - Battery Temperature is ". $result->{$oids{'BatteryTemperature'}} ."C | BatteryTemperature=". 
			      $result->{$oids{'BatteryTemperature'}} .";". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery Temperature.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "OutputOnBattery" {
		my $result=$snmp->get_request( -varbindlist => [$oids{'OutputOnBattery'}]);
		if ( $result && $result->{$oids{'OutputOnBattery'}} == 2) {
			print "OK - Output is not on Battery.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'OutputOnBattery'}} == 1) {
			print "CRITICAL - Output IS on Battery.\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryRemainingTime"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryRemainingTime'}]);
		if ( $result ) {
			(print "OK - Battery Remaining Time is ". $result->{$oids{'BatteryRemainingTime'}} ."sec | BatteryRemainingTime=". 
			      $result->{$oids{'BatteryRemainingTime'}} ."s;". $opt{'w'} .";". $opt{'c'} .";0;\n" and exit($ERRORS{'OK'})) if $result->{$oids{'BatteryRemainingTime'}} > $opt{'w'};
			(print "WARNING - Battery Remaining Time is ". $result->{$oids{'BatteryRemainingTime'}} ."sec | BatteryRemainingTime=". 
			      $result->{$oids{'BatteryRemainingTime'}} ."s;". $opt{'w'} .";". $opt{'c'} .";0;\n" and exit($ERRORS{'WARNING'})) if $result->{$oids{'BatteryRemainingTime'}} > $opt{'c'};
			print "CRITICAL - Battery Remaining Time is ". $result->{$oids{'BatteryRemainingTime'}} ."sec | BatteryRemainingTime=". 
			      $result->{$oids{'BatteryRemainingTime'}} ."s;". $opt{'w'} .";". $opt{'c'} .";0;\n" and exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery Remaining Time.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	
	case "BatteryLevel"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryLevel'}]);
		if ( $result ) {
			(print "OK - Battery Level is ". $result->{$oids{'BatteryLevel'}} ."% | BatteryLevel=". 
			      $result->{$oids{'BatteryLevel'}} ."%;". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'OK'})) if $result->{$oids{'BatteryLevel'}} > $opt{'w'};
			(print "WARNING - Battery Level is ". $result->{$oids{'BatteryLevel'}} ."% | BatteryLevel=". 
			      $result->{$oids{'BatteryLevel'}} ."%;". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'WARNING'})) if $result->{$oids{'BatteryLevel'}} > $opt{'c'};
			print "CRITICAL - Battery Level is ". $result->{$oids{'BatteryLevel'}} ."% | BatteryLevel=". 
			      $result->{$oids{'BatteryLevel'}} ."%;". $opt{'w'} .";". $opt{'c'} .";0;100\n" and exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery Remaining Time.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryFaultBattery"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryFaultBattery'}]);
		if ( $result && $result->{$oids{'BatteryFaultBattery'}} == 2) {
			print "OK - No Battery is faulty.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'BatteryFaultBattery'}} == 1) {
			print "CRITICAL - At least one Battery is faulty.\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryReplacement"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryReplacement'}]);
		if ( $result && $result->{$oids{'BatteryReplacement'}} == 2) {
			print "OK - Battery Replacement indicator is ok.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'BatteryReplacement'}} == 1) {
			print "CRITICAL - Battery Replacement indicator is not ok.\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryChargerFault"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryChargerFault'}]);
		if ( $result && $result->{$oids{'BatteryChargerFault'}} == 2) {
			print "OK - Battery Charger OK.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'BatteryChargerFault'}} == 1) {
			print "CRITICAL - Battery Charger not ok(UPS Internal failure).\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "BatteryLowBattery"{
		my $result=$snmp->get_request( -varbindlist => [$oids{'BatteryLowBattery'}]);
		if ( $result && $result->{$oids{'BatteryLowBattery'}} == 2) {
			print "OK - Battery is not in LowBattery status.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'BatteryLowBattery'}} == 1) {
			print "CRITICAL - Battery is in LowBattery status.\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}
	case "OutputOnByPass"	{
		my $result=$snmp->get_request( -varbindlist => [$oids{'OutputOnByPass'}]);
		if ( $result && $result->{$oids{'OutputOnByPass'}} == 2) {
			print "OK - Output is not on Bypass.\n";
			exit($ERRORS{'OK'});
		}elsif ( $result && $result->{$oids{'OutputOnByPass'}} == 1) {
			print "CRITICAL - Output is on Bypass.\n";
			exit($ERRORS{'CRITICAL'});
		} 
		else { 
			print "ERROR - Could not fetch Battery status.\n";
			exit($ERRORS{'CRITICAL'});
		}
	}else {  
		print "command not understood\n\n"; 
		print $usage; 
		exit($ERRORS{'UNKNOWN'});
	}
};
exit($ERRORS{'UNKNOWN'});
