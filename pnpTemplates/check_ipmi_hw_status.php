<?php
$_WARNRULE = '#FFFF00';
$_CRITRULE = '#FF0000';
$_AREA     = '#256aef';
$_LINE     = '#3152A5';
$_MAXRULE  = '#000000';
$col_fans = array("#6600FF","#6633FF","#6666FF","#6699FF","#66CCFF","#66FFFF","#9900FF","#9933FF","#9966FF","#9999FF","#99CCFF","#99FFFF","#CC00FF","#CC33FF","#CC66FF");
$col_temp = array("#FF0000", "#FF3300", "#FF6600", "#FF9900", "#FFCC00", "#FFFF00", "#FF0033", "#FF3333", "#FF6633", "#FF9933", "#FFCC33", "#FFFF33","#FF0066","#FF3366","#FF6666","#FF9966","#FFCC66");
$col_pow  = array("#336600", "#339900", "#33CC00", "#33FF00", "#33FF33","#66CC00","#66FF00","#66CC33","#66FF33","#66CC66","#66FF66","#99CC00","#99FF00","#99CC33","#99FF33","#99CC66",);


foreach ($this->DS as $KEY=>$VAL) {
	if (preg_match("/rpm/i", $VAL['UNIT'])){
		$fans[]=$KEY;
	}elseif ($VAL['UNIT'] == "C"){
		$temperatures[]=$KEY;
	}elseif ($VAL['UNIT'] == "W"){
		$pows[]=$KEY;
	}else{
		$rest[]=$KEY;
	}
}
#throw new Kohana_exception(print_r($this->DS,true));

$j=0;
$opt[1] = '--slope-mode -l0 --vertical-label "Fanspeed in RPM" --title "' . $this->MACRO['DISP_HOSTNAME'] . ' / ' . $this->MACRO['DISP_SERVICEDESC'] . ' / FANS"';
$def[1] = '';
foreach ($fans as $i){
	$def[1] .= rrd::def		("var$i", $this->DS[$i]['RRDFILE'], $this->DS[$i]['DS'], "AVERAGE");
	$def[1] .= rrd::area	("var$i", $col_fans[$j]."70", rrd::cut($this->DS[$i]["NAME"],18));
	$def[1] .= rrd::line1	("var$i", "#000");
	$def[1] .= rrd::gprint	("var$i", array("LAST", "AVERAGE", "MAX"), "%6.0lf");
$j++;
}

$j=0;
$opt[2] = '--slope-mode -l0 --vertical-label "Temperature in °C" --title "' . $this->MACRO['DISP_HOSTNAME'] . ' / ' . $this->MACRO['DISP_SERVICEDESC'] . ' / Temperature"';
$def[2] = '';
#throw new Kohana_exception(print_r($temperatures,true));
foreach ($temperatures as $i){
	$def[2] .= rrd::def		("var$i", $this->DS[$i]['RRDFILE'], $this->DS[$i]['DS'], "AVERAGE");
	$def[2] .= rrd::area	("var$i", $col_temp[$j]."70", rrd::cut($this->DS[$i]["NAME"],18));
	$def[2] .= rrd::line1	("var$i", "#000");
	$def[2] .= rrd::gprint	("var$i", array("LAST", "AVERAGE", "MAX"), "%6.2lf");
$j++;
}

$j=0;
$opt[3] = '--slope-mode -l0 --vertical-label "Powerconsumption in W" --title "' . $this->MACRO['DISP_HOSTNAME'] . ' / ' . $this->MACRO['DISP_SERVICEDESC'] . ' / Power"';
$def[3] = '';
foreach ($pows as $i){
	$def[3] .= rrd::def		("var$i", $this->DS[$i]['RRDFILE'], $this->DS[$i]['DS'], "AVERAGE");
	$def[3] .= rrd::area	("var$i", $col_pow[$j]."70", rrd::cut($this->DS[$i]["NAME"],18));
	$def[3] .= rrd::line1	("var$i", "#000");
	$def[3] .= rrd::gprint	("var$i", array("LAST", "AVERAGE", "MAX"), "%6.2lf");
$j++;
}
?>
