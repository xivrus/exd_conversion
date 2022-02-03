$host.UI.RawUI.WindowTitle = "CSV -> EXD"

# Functions source: https://www.sans.org/blog/powershell-byte-array-and-hex-functions/
function Convert-ByteArrayToHexString
{
################################################################
#.Synopsis
# Returns a hex representation of a System.Byte[] array as
# one or more strings. Hex format can be changed.
#.Parameter ByteArray
# System.Byte[] array of bytes to put into the file. If you
# pipe this array in, you must pipe the [Ref] to the array.
# Also accepts a single Byte object instead of Byte[].
#.Parameter Width
# Number of hex characters per line of output.
#.Parameter Delimiter
# How each pair of hex characters (each byte of input) will be
# delimited from the next pair in the output. The default
# looks like "0x41,0xFF,0xB9" but you could specify "\x" if
# you want the output like "\x41\xFF\xB9" instead. You do
# not have to worry about an extra comma, semicolon, colon
# or tab appearing before each line of output. The default
# value is ",0x".
#.Parameter Prepend
# An optional string you can prepend to each line of hex
# output, perhaps like '$x += ' to paste into another
# script, hence the single quotes.
#.Parameter AddQuotes
# A switch which will enclose each line in double-quotes.
#.Example
# [Byte[]] $x = 0x41,0x42,0x43,0x44
# Convert-ByteArrayToHexString $x
#
# 0x41,0x42,0x43,0x44
#.Example
# [Byte[]] $x = 0x41,0x42,0x43,0x44
# Convert-ByteArrayToHexString $x -width 2 -delimiter "\x" -addquotes
#
# "\x41\x42"
# "\x43\x44"
################################################################
[CmdletBinding()] Param (
[Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Byte[]] $ByteArray,
[Parameter()] [Int] $Width = 10,
[Parameter()] [String] $Delimiter = ",0x",
[Parameter()] [String] $Prepend = "",
[Parameter()] [Switch] $AddQuotes )
 
if ($Width -lt 1) { $Width = 1 }
if ($ByteArray.Length -eq 0) { Return }
$FirstDelimiter = $Delimiter -Replace "^[\,\:\t]",""
$From = 0
$To = $Width - 1
Do
{
$String = [System.BitConverter]::ToString($ByteArray[$From..$To])
$String = $FirstDelimiter + ($String -replace "\-",$Delimiter)
if ($AddQuotes) { $String = '"' + $String + '"' }
if ($Prepend -ne "") { $String = $Prepend + $String }
$String
$From += $Width
$To += $Width
} While ($From -lt $ByteArray.Length)
}

function Convert-HexStringToByteArray
{
################################################################
#.Synopsis
# Convert a string of hex data into a System.Byte[] array. An
# array is always returned, even if it contains only one byte.
#.Parameter String
# A string containing hex data in any of a variety of formats,
# including strings like the following, with or without extra
# tabs, spaces, quotes or other non-hex characters:
# 0x41,0x42,0x43,0x44
# \x41\x42\x43\x44
# 41-42-43-44
# 41424344
# The string can be piped into the function too.
################################################################
[CmdletBinding()]
Param ( [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [String] $String )
 
#Clean out whitespaces and any other non-hex crud.
$String = $String.ToLower() -replace '[^a-f0-9\\,x\-\:]',"
 
#Try to put into canonical colon-delimited format.
$String = $String -replace '0x|\x|\-|,',':'
 
#Remove beginning and ending colons, and other detritus.
$String = $String -replace '^:+|:+$|x|\',"
 
#Maybe there's nothing left over to convert...
if ($String.Length -eq 0) { ,@() ; return }
 
#Split string with or without colon delimiters.
if ($String.Length -eq 1)
{ ,@([System.Convert]::ToByte($String,16)) }
elseif (($String.Length % 2 -eq 0) -and ($String.IndexOf(":") -eq -1))
{ ,@($String -split '([a-f0-9]{2})' | foreach-object { if ($_) {[System.Convert]::ToByte($_,16)}}) }
elseif ($String.IndexOf(":") -ne -1)
{ ,@($String -split ':+' | foreach-object {[System.Convert]::ToByte($_,16)}) }
else
{ ,@() }
#The strange ",@(...)" syntax is needed to force the output into an
#array even if there is only one element in the output (or none).
}


while ($true) {

"Drag and drop EXH file and press Enter."
$exh_path = Read-Host ' '
if ( $exh_path.StartsWith('"') -and $exh_path.EndsWith('"')) {
    $exh_path = $exh_path.Substring(1, $exh_path.Length-2)
}
if (!$(Test-Path $exh_path)) {
    "EXH file wasn't found at $exh_path.`n"
    pause
    exit
}
$exh_file_name = $(Split-Path $exh_path -Leaf) -replace ".{4}$"
$current_dir = $(Split-Path $exh_path -Parent)
$EXD_DIR          = "$current_dir"
$BIN_DIR          = "$current_dir\bin"
$CSV_DIR          = "$current_dir\csv"

$csv_files = Get-ChildItem -Path "$CSV_DIR\$($exh_file_name)_*_*.csv" -Name
$csv_path = "$CSV_DIR\"
if ($csv_files.Count -gt 1) {
    "Several CSV files were found:"
    for ($_i = 0; $_i -lt $csv_files.Count; $_i++) {
        "  $($_i+1). $($csv_files[$_i])"
    }
    while ($true) {
        $_choice = [int]$(Read-Host "Choose one")
        $_choice--
        if ( ($_choice -gt -1) -and ($_choice -lt $csv_files.Count) ) {
            "$($csv_files[$_choice]) was chosen."
            $csv_path += $csv_files[$_choice]
            break
        }
        "Try again."
    }
} else {
    "$csv_files was found."
    $csv_path += $csv_files
}
$exd_file_name = $(Split-Path $csv_path -Leaf).TrimEnd(".csv")

$bin_path = "$BIN_DIR\$exd_file_name.bin"
if (!$(Test-Path $bin_path)) {
    "BIN file wasn't found at $bin_path.`n"
    pause
    break
}
$exd_path = "$EXD_DIR\$exd_file_name.exd"
if (Test-Path $exd_path) {
    $_answer = $(Read-Host "$exd_path already exists. Overwrite? (Y/n)").ToLower()
    switch ($_answer) {
        "" {}
        "y" {}
        default { break }
    }
}
$_answer = $(Read-Host "Remove '<index>_' from the start of translation fields? (y/N)").ToLower()
switch ($_answer) {
    "y" { $REMOVE_INDEXES = $true; break }
    default { $REMOVE_INDEXES = $false }
}

$exh = $null
$bin = $null
$csv = $null
while ($true) {
    $exh = [System.IO.File]::ReadAllBytes($exh_path)
    $bin = [System.IO.File]::ReadAllBytes($bin_path)
    $csv = [System.IO.File]::ReadAllBytes($csv_path)                     # For taking strings as byte arrays
    if ($exh -and $bin -and $csv) { break }
    "Error while trying to read following file(s):"
    if (!$exh) { "$exh_path" }
    if (!$bin) { "$bin_path" }
    if (!$csv) { "$csv_path" }
    "If they exist they could be locked by some program."
    $null = Read-Host "Press Enter when you're ready to try again."
}
$csv_string = Get-Content $csv_path -Raw -Encoding Ascii -ReadCount 0    # For easier parsing the file
$csv_string = $csv_string[0]                                             # Making a clean string

# Step 0. Collect data from EXH file
$data_chunk_size = [uint32](Convert-ByteArrayToHexString $exh[0x6..0x7] -Delimiter '' -Prepend '0x')
$number_of_datasets = [uint32](Convert-ByteArrayToHexString $exh[0x8..0x9] -Delimiter '' -Prepend '0x')
$string_offsets_in_datachunks = New-Object System.Collections.ArrayList
for ($_i = 0; $_i -lt $number_of_datasets; $_i++) {
    $_offset = 0x20 + $_i*4
    if ( @(Compare-Object $exh[$_offset..($_offset+1)] @( 0x00, 0x00 ) ).Length -eq 0 ) {
        $_string_offset = [uint32](Convert-ByteArrayToHexString $exh[($_offset+2)..($_offset+3)] -Delimiter '' -Prepend '0x')
        $null = $string_offsets_in_datachunks.Add($_string_offset)
    }
}

$MAC_NEW_LINE = [byte]0x0D
$UNIX_NEW_LINE = [byte]0x0A
# Adjust according to your choice in _EXDtoCSV.ps1
$NEW_LINE = $UNIX_NEW_LINE
$NEW_LINE_STRING = [System.Text.Encoding]::UTF8.GetString($NEW_LINE)

# Step 1. Collect raw indexes, strings, and their offsets into the $row_data table
#  Expected format of the rows:
#    0xXXXXXXXX||<translation>||<source><new_line>0xYYY...
#        1         2         3         4         5
#    678901234567890123456789012345678901234567890123456
#  <Source> field is ignored here.
#  Afaik FFXIV doesn't have any strings that start with 0x, so it should be safe.
#  If there are several strings per row, there are separated by 0x00 byte in
#  source string. We'll be looking for this byte here to separate the strings
#  in a row and get their new offsets for an according row chunk.
$row_start_index = 0
$row_end_index = 0
$row_data = New-Object System.Collections.ArrayList
$SEARCH_STRING = "$($NEW_LINE_STRING)0x"
$CSV_SEPARATOR = '|'
$EXD_INDEX_LENGTH = "0x00000000".Length
$NEW_LINE_LENGTH = $NEW_LINE.Length
do {
    $row_start_index = $csv_string.IndexOf($SEARCH_STRING, $row_end_index) + $NEW_LINE_LENGTH
    $row_end_index = $csv_string.IndexOf($SEARCH_STRING, $row_start_index) - $NEW_LINE_LENGTH
    if ($row_end_index -eq (-1 - $NEW_LINE_LENGTH)) {
        $row_end_index = $csv_string.Length - $NEW_LINE_LENGTH
    }

    $exd_index = [uint32]($csv_string.Substring($row_start_index, $EXD_INDEX_LENGTH))
    $exd_index_hex = "{0:X}_" -f $exd_index

    $row_translation_start_index = $csv_string.IndexOf($CSV_SEPARATOR, $row_start_index) + 1
    $row_translation_end_index = $csv_string.IndexOf("$CSV_SEPARATOR$CSV_SEPARATOR", $row_translation_start_index) - 1
    $row_translation_length = $row_translation_end_index - $row_translation_start_index + 1
    if ($REMOVE_INDEXES -and $csv_string.Substring($row_translation_start_index, $row_translation_length).StartsWith($exd_index_hex) ) {
        $row_translation_start_index += $exd_index_hex.Length
        $row_translation_length = $row_translation_end_index - $row_translation_start_index + 1
    }
    if ($row_translation_length -gt 0) {
        $translation_bytes = $csv[$row_translation_start_index..$row_translation_end_index]
    } else { $translation_bytes = @() }
    
    $strings_offsets = New-Object System.Collections.ArrayList
    $null = $strings_offsets.Add( 0 )    # First string always starts at offset 0
    for ($_index = 0; $_index -lt $translation_bytes.Count; $_index++) {
        if ($translation_bytes[$_index] -eq [byte]0x00) {
            $null = $strings_offsets.Add($_index + 1)
        }
    }

    $null = $row_data.Add(@($exd_index, $translation_bytes, $strings_offsets) )
} while ($csv_string.IndexOf($SEARCH_STRING, $row_end_index) -ne -1)

# Step 2. Edit BIN data
for ($_i = 0; $_i -lt $row_data.Count; $_i++) {
    $_offset = $_i * $data_chunk_size
    $_string_offsets_bytes = New-Object System.Collections.ArrayList
    foreach ($_raw_data_piece in $row_data[$_i][2]) {
        $_string_offset_array = New-Object System.Collections.ArrayList
        foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_raw_data_piece )) ) {
            $null = $_string_offset_array.Add( $_byte )
        }
        $null = $_string_offsets_bytes.Add($_string_offset_array)
    }
    $_count = 0
    for ($_j = 0; $_j -lt $data_chunk_size; $_j++) {
        if ($string_offsets_in_datachunks -contains $_j) {
            for ($_k = 0; $_k -lt 4; $_k++) {
                if ($null -eq $_string_offsets_bytes[$_count]) {
                    $bin[($_offset+$_j+$_k)] = [byte]0x00
                } else {
                    $bin[($_offset+$_j+$_k)] = $_string_offsets_bytes[$_count][$_k]
                }
            }
            $_count++
        }
    }
}

# Step 3. Setting up actual data table that's going to go in file
#         + Remembering offsets for the offset table
$offset_table_size = $row_data.Count * 8
$data_table_offset = $offset_table_size + 0x20

$index_offset_table = New-Object System.Collections.ArrayList
$data_table = New-Object System.Collections.ArrayList
$_current_offset = $data_table_offset
# $_i = 1 # For debug to jump to specified string in CSV
for ($_i = 0; $_i -lt $row_data.Count; $_i++)
{
    $null = $index_offset_table.Add(@($row_data[$_i][0],$_current_offset) )
    $_size = $data_chunk_size + $row_data[$_i][1].Length
    $_zeros = 4 - (2 + $_size) % 4     # Seems like padding is always aligned to 4
    foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f ($_size + $_zeros)) ) )
    {
        $null = $data_table.Add( $_byte )
    }
    $null = $data_table.Add( [byte]0x00 )
    $null = $data_table.Add( [byte]0x01 )
    for ($_j = 0; $_j -lt $data_chunk_size; $_j++)
    {
        $null = $data_table.Add( $bin[($_i*$data_chunk_size + $_j)] )
    }
    if ($row_data[$_i][1].Count -gt 0)
    {
        foreach ($_byte in $row_data[$_i][1] )
        {
            $null = $data_table.Add( $_byte )
        }
    }
    for ($_j = 0; $_j -lt $_zeros; $_j++)
    {
        $null = $data_table.Add( [byte]0x00 )
    }
    $_current_offset += 6 + $_size + $_zeros
}
[byte[]]$data_table = $data_table.ToArray() # Checking that we've got only bytes

# Step 4. Create offset table
$offset_table = [System.Collections.ArrayList]@()
foreach ($_index_offset_piece in $index_offset_table)
{
    foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_index_offset_piece[0]) ) )
    {
        $null = $offset_table.Add( $_byte )
    }
    foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_index_offset_piece[1]) ) )
    {
        $null = $offset_table.Add( $_byte )
    }
}

# Step 5. Header
$exd_header = [Byte[]]@(0x45,0x58,0x44,0x46,0x00,0x02,0x00,0x00) + 
    $(Convert-HexStringToByteArray ("{0:X8}" -f $offset_table.Count) ) +
    $(Convert-HexStringToByteArray ("{0:X8}" -f $data_table.Count) ) +
    @([byte]0x00) * 16

# Step 6. Check everything and put everything in a new file
if (($null -eq $exd_header) -or ($null -eq $offset_table) -or ($null -eq $data_table)) {
    "Something went wrong. Use IDE (e.g. ISE) to debug"
    "or scroll up to read errors."
    Pause
    Return
}
Set-Content -Value ($exd_header + $offset_table + $data_table) -Encoding Byte -Path $exd_path
Remove-Variable data_table
}