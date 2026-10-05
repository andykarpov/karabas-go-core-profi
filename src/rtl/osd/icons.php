<?php

$filename = 'icons4.pf';
$size = filesize($filename);
$f = fopen($filename, 'rb');
$contents = fread($f, $size);
fclose($f);

$o = fopen('icons.bit', 'w');

$a = 0;
for ($j=0; $j<256; $j++) {
	for ($i=0; $i<8; $i++) {
		fwrite($o,  (((ord($contents[$j]) >> (7-$i)) & 1) ? '1': '0') . (($a < 256*8-1) ? " " : ""));
		if (($a+1) % 16 == 0) fwrite($o, "\n");
		$a++;
	}
}

fclose($o);
