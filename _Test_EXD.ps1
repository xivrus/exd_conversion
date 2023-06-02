# Sample script for debugging EXHF & EXDF classes

using module .\lib\EXHF.psm1
using module .\lib\EXDF.psm1

$exh_path = '.\current\exh_source\exd\item.exh'
$exd_path = '.\current\exd_source\exd\item_0_en.exd'

$item_exh = [EXHF]::new($exh_path)
# $item_exh.Export('.\item_custom.exh')

$item_0_exd = [EXDF]::new($item_exh, $exd_path)
$item_0_exd.ExportEXD('.\item_custom.exd')

$hash_original = Get-FileHash -Path $exd_path -Algorithm MD5
$hash_export = Get-FileHash -Path '.\item_custom.exd' -Algorithm MD5
'Is export identical: ' + $($hash_original.Hash -eq $hash_export.Hash)
