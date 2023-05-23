# Sample script for debugging EXHF & EXDF classes

using module .\lib\EXHF.psm1
using module .\lib\EXDF.psm1

$exh_path = '.\current\exh_source\exd\item.exh'

$item_exh = [EXHF]::new( $exh_path )
$item_exh.Export('.\item_custom.exh')

$item_0_exd = [EXDF]::new(
	$item_exh.GetPage(0),
	$item_exh.GetLang('en'),
	'.\current\exd_source\exd\item_0_en.exd'
)

Pause
