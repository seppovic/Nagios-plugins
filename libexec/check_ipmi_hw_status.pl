#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;


use lib "/usr/local/nagios/libexec"; # Pfad zur util.pm !!
my $TIMEOUT=15; my %ERRORS=(0 => 'OK',1 =>'WARNING',2 =>'CRITICAL',3 => 'UNKNOWN', 4 => 'DEPENDENT'); 
#use utils qw ($TIMEOUT %ERRORS);


my $usage= qq ~
usage: $0 -H <hostname> -U <Username> -P <Password> -M <MachinePreset> [ -F <config File> -T <Timeout> -d ] | -h 

\t-H\t IP of Host
\t-U\t Username for ipmi User
\t-P\t Password
\t-M\t Machine Preset
\t\t possible Values:
\t\t fsc
\t\t DELL
\t\t more to come
\t-F\t specifiy a config File with different presets.
\t\t Presets contain Sensors to read, Warn/Crit values, Filter strings etc. 
\t-T\t optional: Timeout in seconds
\t\t default: $TIMEOUT seconds
\t-d\t optional: debug output on stderr 
\t-h\t prints this helpmessage

~;

my %opt=();
getopts('h?H:U:P:M:dT:F:',\%opt) or (print $usage and exit(2));
(print $usage and exit(2)) if $opt{'h'} or $opt{'?'}; 
(print $usage and exit(2)) if !defined $opt{'H'} || $opt{'H'}!~/\d+\.\d+\.\d+\.\d+/;
$opt{'T'}=$opt{'T'} || $TIMEOUT;
(print $usage and exit(2)) if !defined $opt{'P'};
(print $usage and exit(2)) if !defined $opt{'U'};
(print $usage and exit(2)) if !defined $opt{'M'};
(print $usage and exit(3)) if $ARGV[0];



my %MaschinePresets;

if ( defined $opt{'F'} ) {
	%MaschinePresets= %{_readConfig($opt{'F'})};
}else { 
	%MaschinePresets= (	
		'fsc' => { 
			'Power Consumption' => {
				'value' =>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' => {
					'Other Units Based Sensor (Bh)'	=>	['*'],
				}, 
			},
			'Temperature'	=>	{
				'value'	=>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' =>	{
					'Temperature (1h)'	=>	['*'],
				},
				'Warn'	=>	[
					'Ambient>27',
				],
				'Crit'	=>	[
					'Ambient>32',
				],
				'Filter'	=>	[
					'N/A',
				],
			},
			'Fans'	=>	{
				'value'	=>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' =>	{
					'Fan (4h)'	=>	['*'],
				},
				'Filter'	=>	[
					'N/A',
				],
			},
			'HW Status'	=>	{
				'value'	=>	'Sensor Event',
				'perf'	=>	undef,
				'Sensors'	=>	{
					'OEM PSU Status (E8h)'	=>	['*'],
					'OEM Fan Status (E6h)'	=>	['*'],
				},
				'Crit'	=>	[
					'!Power supply - OK',
					'!FAN on, running',
					'!FAN not installed',
				],
				'Filter'	=>	[
					'Unknown',
				],
			},		
		},
		'DELL' => { 
			'HW Status'	=>	{
				'value'	=>	'Sensor Event',
				'perf'	=>	undef,
				'Sensors'	=>	{
					'Power Supply (8h)'	=>	['PS Redundancy'],
				},
				'Crit'	=>	[
					'Redundancy Lost',
				],
				'Filter'	=>	[
					'Unknown',
				],
			},		
			'Power Consumption' => {
				'value' =>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' => {
					'Current (3h)'	=>	['*'],
				},
				'Warn'	=>	[
					'Pwr Consumption>1260',
				],
				'Crit'	=>	[
					'Pwr Consumption>1386',
					'N/A'
				],
				 
			},
			'Temperature'	=>	{
				'value'	=>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' =>	{
					'Temperature (1h)'	=>	['*'],
				},
				'Warn'	=>	[
					'Inlet Temp>27',
				],
				'Crit'	=>	[
					'Inlet Temp>32',
				],
				'Filter'	=>	[
					'N/A',
				],
			},
			'Fans'	=>	{
				'value'	=>	'Sensor Reading',
				'perf'	=>	['Sensor Min. Reading', 'Sensor Max. Reading'],
				'Sensors' =>	{
					'Fan (4h)'	=>	['*'],
				},
				'Warn'	=>	[
					'<840',
				],
				'Crit'	=>	[
					'<100',
				],
				'Filter'	=>	[
					'N/A',
				],
			},
			'Battery' =>	{
				'value'	=>	'Sensor Event',
				'Sensors' =>	{
					'Battery (29h)'	=>	['*'],
				},
				'perf'	=>	undef,
				'Crit'	=>	[
					'!OK',
				],
			},
		},
	);

}


# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
        print "UNKNOWN - Plugin Timed out\n";
        exit 3;
};
alarm($opt{'T'});


main();
sub main{
	my $SensorData= _get_ipmi_data( {host => $opt{'H'}, username => $opt{'U'}, password => $opt{'P'}} );
	my @output=(); my @nonOK; my @perfout=(); my $global_ret_code = 0; my $current_ret_code = 0;
	
	for my $component ( sort(keys %{$MaschinePresets{$opt{'M'}}}) ) {									#$component='HW Status' from Preset
		for my $sensor ( sort(keys %{$MaschinePresets{$opt{'M'}}->{$component}->{'Sensors'}}) ) {		#$sensor='OEM PSU Status (E8h)' from Preset
			my @iterator;
			if ( $MaschinePresets{$opt{'M'}}->{$component}->{'Sensors'}->{$sensor}->[0] eq '*' ) {
				for my $ipmiSensor ( keys %{$SensorData->{$sensor}} ) {   								#$ipmiSensor='FAN1 PSU1' from ipmi request
					push @iterator,  $ipmiSensor;	
				}
		    }else{ 
				@iterator= @{$MaschinePresets{$opt{'M'}}->{$component}->{'Sensors'}->{$sensor}};		#@iterator =  $MaschinePresets{FSC}->{HW Status}->{'Sensors'}->{OEM PSU Status (E8h)}  <=> 'Pwr Consumption'
		    }
		    ITERATE: for my $ipmiSensor ( sort(@iterator) ) {
		    	my $val= undef;
		    	$val= $SensorData->{$sensor}->{$ipmiSensor}->{$MaschinePresets{$opt{'M'}}->{$component}->{'value'}} if exists $SensorData->{$sensor}->{$ipmiSensor}->{$MaschinePresets{$opt{'M'}}->{$component}->{'value'}};
		    	
		    	next ITERATE if _FilterOut({'sensor' => $ipmiSensor, 'val' => $val, 'filter' => $MaschinePresets{$opt{'M'}}->{$component}->{'Filter'}});
						    		    	
		    	($global_ret_code,$current_ret_code)=_get_criticality( {'sensor' => $ipmiSensor, 'old_ret' => $global_ret_code, 'val' => $val, 'warn' => $MaschinePresets{$opt{'M'}}->{$component}->{'Warn'}, 'crit' => $MaschinePresets{$opt{'M'}}->{$component}->{'Crit'} });
	    	
	    		# store output in array for later use
		    	if ( defined $current_ret_code && $current_ret_code != 0 ) {
		    		push @nonOK, $ipmiSensor.'='.$val ;
		    	} else { 
		    		push @output, $ipmiSensor.'='.$val ;
		    	}
			
				# process, normalice and store perfdata in array for later use
				if (defined $MaschinePresets{$opt{'M'}}->{$component}->{'perf'}){
					my $min=$SensorData->{$sensor}->{$ipmiSensor}->{$MaschinePresets{$opt{'M'}}->{$component}->{'perf'}->[0]};
			    	my $max=$SensorData->{$sensor}->{$ipmiSensor}->{$MaschinePresets{$opt{'M'}}->{$component}->{'perf'}->[1]};
					push @perfout, _normalizePerfdata($ipmiSensor.'='.$val.';;;'. $min .';'. $max ); 	
				}
			}
		}
	}
	#### getting new data for harddrive status: ipmi does not let us do this in one request :( 
	#warn 'main: doing 2nd request to Host to get chassis status' if $opt{'d'};
	#my ($errCode, $errString)= _get_ipmi_status_data({host => $opt{'H'}, username => $opt{'U'}, password => $opt{'P'}});
	#$global_ret_code = $errCode if $errCode > $global_ret_code;
	#print $ERRORS{$global_ret_code} ." - ". join (" ", @$errString,@nonOK) ." |". (join " ", @perfout) ."\n";
	# print output and exit to nagios
	print $ERRORS{$global_ret_code} ." - ". join (" ", @nonOK) ." |". (join " ", @perfout) ."\n";
	exit($global_ret_code);
}#END

sub _get_ipmi_status_data{
	my $params = shift @_;
	
	my $ipmiSTATUSCMD= readpipe('which ipmitool 2>/dev/null');
	chomp($ipmiSTATUSCMD);
	chomp($ipmiSTATUSCMD = readpipe('which ipmitool')) if -e $ipmiSTATUSCMD && -x $ipmiSTATUSCMD;
	$ipmiSTATUSCMD = '/usr/local/sbin/ipmitool' if -e '/usr/local/sbin/ipmitool' && -x '/usr/local/sbin/ipmitool';
	$ipmiSTATUSCMD = '/usr/share/sbin/ipmitool' if -e '/usr/share/sbin/ipmitool' && -x '/usr/share/sbin/ipmitool';
	(print "UNKNOWN - Could not find ipmitool executable, make sure free-ipmi package is installed\n" and exit(3)) if ! $ipmiSTATUSCMD;
	
	warn '_get_ipmi_data: prozessing '. $ipmiSTATUSCMD .' -I lanplus -H '. $params->{'host'} .' -U '. $params->{'username'} .' -P '. $params->{'password'} .' chassis status' if $opt{'d'};
	my @lines=readpipe($ipmiSTATUSCMD .' -I lanplus -H '. $params->{'host'} .' -U '. $params->{'username'} .' -P '. $params->{'password'} .' -L user chassis status') or (print "UNKNOWN - $?" and exit(3));	
	
	# do inline criticality checking
	my $errCode=0; my @errString;
	
	for ( @lines ){
		if( /^Drive Fault/ && !/false\s*$/ ){
				$errCode=2;
				push @errString, 'At least 1 Harddrive is faulty.';
		}
		if( /^Cooling\/fan fault/ && !/false\s*$/) {
				$errCode=2;
				push @errString, 'At least 1 Fan is faulty.';
		}
	}
	return ($errCode, \@errString);
}

sub _FilterOut{
	my $c= shift @_;
	for my $filterExpr ( @{$c->{'filter'}} ){
		warn "_FilterOut: $c->{'sensor'} with value:$c->{'val'} filtered\n" if (!$c->{'val'} || ($c->{'val'} eq $filterExpr)) && $opt{'d'};

	    return 1 if !$c->{'val'} || $c->{'val'} eq $filterExpr;
	}
	warn "_FilterOut: $c->{'sensor'} with value:$c->{'val'} passed the Filter\n" if $opt{'d'};
	return 0;
	
}

sub _normalizePerfdata{
	my $in = shift @_;
	if (my ($name, $val, $UOM, $warn, $crit, $min, $max) = ($in=~/^(.*)=\D*(\d+.\d*|\d+)(.*);(.*);(.*);(.*);(.*)/) ){
		$val = sprintf '%.2f', $val;
		$UOM = $1 if $UOM=~/^.*?(\w+)\s*$/;
		$warn = sprintf '%.2f', $1 if $warn=~/\D*(\d+|\d+.\d*)\D*/;
		$crit = sprintf '%.2f', $1 if $crit=~/\D*(\d+|\d+.\d*)\D*/;
		$min = sprintf '%.2f', $1 if $min=~/\D*?(-*\d+|-*\d+.\d*)\D*/;
		$max = sprintf '%.2f', $1 if $max=~/\D*?(-*\d+|-*\d+.\d*)\D*/;
		$name=~s/^\W*(\w+)\W*$/$1/;
		warn "_normalizePerfdata: normalizing Input:\n --> $in\nto:\n --> ".'\''. $name .'\'='. $val . $UOM .';'. $warn .';'. $crit .';'. $min .';'. $max if $opt{'d'};
		return '\''. $name .'\'='. $val . $UOM .';'. $warn .';'. $crit .';'. $min .';'. $max;
	}else{
		warn "_normalizePerfdata: Could not understand input Data, returning empty String\n"if $opt{'d'};
		return '';
	}
}

sub _get_criticality{
	use Scalar::Util qw(looks_like_number);
	my $c= shift @_;
	
	warn "_get_criticality: determin criticality for $c->{'sensor'} with value:$c->{'val'}; old criticality was $c->{'old_ret'} \n" if $opt{'d'};
	
	#return $c->{'old_ret'} if $c->{'old_ret'} >=2;
	return ($c->{'old_ret'},undef) if !$c->{'crit'} && !$c->{'warn'};
	
	#print $c->{'sensor'}.": ". $c->{'val'} ."\n";
	my @valWords = split ' ', $c->{'val'}; 
	if ( looks_like_number($valWords[0]) ){
		
		if ( $c->{'crit'} ){
			for my $critter ( @{$c->{'crit'}} ){
				
				next if $critter !~ /^$c->{'sensor'}/i;		    
			    if ( $critter =~ /.*\>\D*(\d+.\d*|\d+)/ ) { # > contains a gt char

			    	return (2,2)  if $1 <=  $valWords[0];
			    }
			    if ( $critter =~ /.*\<\D*(\d+.\d*|\d+)/ ) { # < contains a lt char
			    	return (2,2) if $1 >=  $valWords[0];
			    }
			}     
		}
		if ( $c->{'warn'} ){
			for my $warner ( @{$c->{'warn'}} ){
				
				next if $warner !~ /^$c->{'sensor'}/i;		    
			    if ( $warner =~ /.*\>\D*(\d+.\d*|\d+)/ ) { # > contains a gt char
			    	return ($c->{'old_ret'},1) if $1 <=  $valWords[0] && $c->{'old_ret'} != 0;
			    	return (1,1) if $1 <=  $valWords[0] && $c->{'old_ret'} == 0;
			    }
			    if ( $warner =~ /.*\<\D*(\d+.\d*|\d+)/ ) { # < contains a lt char
			    	return ($c->{'old_ret'},1) if $1 >=  $valWords[0] && $c->{'old_ret'} != 0;
			    	return (1,1) if $1 <=  $valWords[0] && $c->{'old_ret'} == 0;
			    }
			} 
		}
		return ($c->{'old_ret'},0);

	}else{
		if ( $c->{'crit'} ) {
			my $cflag=0; 
			my $clen= @{$c->{'crit'}};
			
			
			for my $critter ( @{$c->{'crit'}} ){
				
			    if( substr($critter, 0, 1) eq '!'){
			    	my $localcritter = substr $critter, 1;
			    	if ($c->{'val'} =~ /$localcritter/ ){
			    		$clen--;		    		
			    	}
			    }else{
			    	$clen--;
			    	if ($c->{'val'} =~ /\Q$critter\E/){
			    		$cflag++;
			    	}
			    }
			}
			return (2,2) if ($clen == @{$c->{'crit'}}) || $cflag >=1 ;
		}
		if ( $c->{'warn'} ) {
			my $wflag=0;
			my $wlen= @{$c->{'warn'}};
			for my $warner ( @{$c->{'warn'}} ){
			    		    
			    if( substr($warner, 0, 1) eq '!'){
			    	my $localwarner = substr $warner, 1;
			    	if ($c->{'val'} =~ /$localwarner/ ){
			    		$wlen--;
			    	}
			    }else{
			    	$wflag = 1 if $c->{'val'} =~ /$warner/;
			    }
			}
			return ($c->{'old_ret'},1) if ($wlen == @{$c->{'warn'}} || $wflag >=1) && $c->{'old_ret'} != 0;
			return (1,1) if ($wlen == @{$c->{'warn'}} || $wflag >=1) && $c->{'old_ret'} == 0;
		}
		return ($c->{'old_ret'},0);
	}
}

sub _get_ipmi_data{
	my $params = shift @_;
	
	my $ipmiCMD= readpipe('which ipmi-sensors 2>/dev/null');
	chomp($ipmiCMD);
	chomp($ipmiCMD = readpipe('which ipmi-sensors')) if -e $ipmiCMD && -x $ipmiCMD;
	$ipmiCMD = '/usr/local/sbin/ipmi-sensors' if -e '/usr/local/sbin/ipmi-sensors' && -x '/usr/local/sbin/ipmi-sensors';
	$ipmiCMD = '/usr/share/sbin/ipmi-sensors' if -e '/usr/share/sbin/ipmi-sensors' && -x '/usr/share/sbin/ipmi-sensors';
	(print "UNKNOWN - Could not find ipmi-sensors executable, make sure free-ipmi package is installed\n" and exit(3)) if ! $ipmiCMD;
	
	warn '_get_ipmi_data: prozessing '. $ipmiCMD .' -h '. $params->{'host'} .' -u '. $params->{'username'} .' -p '. $params->{'password'} .' -l user --interpret-oem-data --quiet-cache --sdr-cache-recreate --no-header-output --output-sensor-state -v'."\n" if $opt{'d'};
	my @lines=readpipe($ipmiCMD .' -h '. $params->{'host'} .' -u '. $params->{'username'} .' -p '. $params->{'password'} .' -l user --interpret-oem-data --quiet-cache --sdr-cache-recreate --no-header-output --output-sensor-state -v') or (print "UNKNOWN - $?" and exit(3));	
	#my @lines= <DATA>;
	
	
	my $label; my $value; my $Type; my $Name;
	my %Sensors; my $curr_Sensor;

	for my $line ( @lines ) {
		$label='';
		$value='';
				
		if ( $line =~ /^\s*$/ ) {
			$Sensors{$Type}{$Name}=$curr_Sensor if !exists $Sensors{$Type}{$Name} || scalar(keys %{$Sensors{$Type}{$Name}}) < scalar(keys %{$curr_Sensor}) ;
			$Type='';
			$Name='';
			undef $curr_Sensor;
		}else{
			chomp $line;
			($label, $value)=split(': ', $line);
			
			$Name= $value if $label eq 'ID String';
			$Type= $value if $label eq 'Sensor Type';
			$curr_Sensor->{$label}=$value;	
		}    
	}
	warn Dumper(\%Sensors) ."_get_ipmi_data: parsed ipmi output to the data strukture above." if $opt{'d'};
	return \%Sensors;
}

sub _readConfig{
	my $f= shift @_;
	use YAML::Tiny;
	my $cfg = YAML::Tiny->read($f) if -f $f; 
	warn Dumper($cfg) if $opt{'d'};
	return $cfg->[0];
}
