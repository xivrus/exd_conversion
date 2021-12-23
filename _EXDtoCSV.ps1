$host.UI.RawUI.WindowTitle = "EXD -> CSV"

# Function source: # Source: https://www.sans.org/blog/powershell-byte-array-and-hex-functions/

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


while ($true) {

"Drag and drop EXH file and press Enter."
$exh_path = Read-Host ' '
if ( $exh_path.StartsWith('"') -and $exh_path.EndsWith('"')) {
    $exh_path = $exh_path.Substring(1, $exh_path.Length-2)
}
if (!$(Test-Path $exh_path)) {
    "EXH file wasn't found at $exh_path.`n"
    continue
}
$exh_file_name = $(Split-Path $exh_path -Leaf) -replace ".{4}$"
$current_dir = $(Split-Path $exh_path -Parent)
$EXD_DIR          = "$current_dir"
$BIN_DIR          = "$current_dir\bin"
$CSV_DIR          = "$current_dir\csv"
$EXD_SOURCE_DIR = "$current_dir\source"

$exd_files = Get-ChildItem -Path "$EXD_DIR\$($exh_file_name)_*_*.exd" -Name
$exd_path = "$EXD_DIR\"
if ($null -eq $exd_files) {
    "Suitable .exd file with the name `"$exh_file_name`" wasn't found."
    "If there's no `"_en`" at the end of the file name"
    "then this file is not language file and you shouldn't touch it.`n"
    continue
}
if ($exd_files.Count -gt 1) {
    "Several EXD files were found:"
    for ($_i = 0; $_i -lt $exd_files.Count; $_i++) {
        "  $($_i+1). $($exd_files[$_i])"
    }
    while ($true) {
        $_choice = [int]$(Read-Host "Choose one")
        $_choice--
        if ( ($_choice -gt -1) -and ($_choice -lt $exd_files.Count) ) {
            "$($exd_files[$_choice]) was chosen."
            $exd_path += $exd_files[$_choice]
            break
        }
        "Try again."
    }
} else {
    "$exd_files was found."
    $exd_path += $exd_files
}
$exd_file_name = $(Split-Path $exd_path -Leaf).TrimEnd(".exd")

$csv_path = "$CSV_DIR\$exd_file_name.csv"
if (Test-Path $csv_path) {
    $_answer = $(Read-Host "$csv_path already exists. Overwrite? (Y/n)").ToLower()
    $_is_answer_no = $false
    switch ($_answer) {
        "n" { $_is_answer_no = $true }
        default { }
    }
    if ($_is_answer_no) {
        ""
        continue
    }
}
$_answer = $(Read-Host "Add '<index>_' at the start of translation fields? (Y/n)").ToLower()
switch ($_answer) {
    "n" { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $false; break }
    default { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $true }
}


if (!$(Test-Path $CSV_DIR)) { New-Item $CSV_DIR -ItemType Directory }
if (!$(Test-Path $BIN_DIR)) { New-Item $BIN_DIR -ItemType Directory }
if (!$(Test-Path $EXD_SOURCE_DIR)) { New-Item $EXD_SOURCE_DIR -ItemType Directory }
$bin_path = "$BIN_DIR\$exd_file_name.bin"
$exd_source_path = "$EXD_SOURCE_DIR\$exd_file_name.exd"
if (!$(Test-Path $exd_source_path)) { Copy-Item $exd_path $exd_source_path }

$exh_bytes = $null
$exd_bytes = $null
$exd_source_bytes = $null
while ($true) {
    $exh_bytes = [System.IO.File]::ReadAllBytes($exh_path)
    $exd_bytes = [System.IO.File]::ReadAllBytes($exd_path)
    $exd_source_bytes = [System.IO.File]::ReadAllBytes($exd_source_path)
    if ($exh_bytes -and $exd_bytes -and $exd_source_bytes) { break }
    "Error while trying to read one of the files (or both)."
    "The file(s) is/are probably locked by some program."
    $null = Read-Host "Press Enter when you're ready to try again."
}

$data_chunk_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x6..0x7] -Delimiter '' -Prepend '0x')
$offset_table_size = [uint32](Convert-ByteArrayToHexString $exd_bytes[0x8..0xB] -Delimiter '' -Prepend '0x')
# $data_section_size = [uint32](Convert-ByteArrayToHexString $exd_bytes[0xC..0xF] -Delimiter '' -Prepend '0x') # Unused apparently

# To avoid wack UTF-8 encoding of Windows PowerShell we'll be working directly with bytes instead.
# The following loop will build the resulting CSV block by block.
$result_file = New-Object System.Collections.ArrayList
# Binary data will be put in a separate file and then combined as one.
$source_binary_file = New-Object System.Collections.ArrayList

$MAC_NEW_LINE = [byte]0x0D
$UNIX_NEW_LINE = [byte]0x0A
# Unix is recommended since it's easier to recover lost bytes
# in case a text editor of your choice decides to change
# all Mac new lines to Unix ones. Doesn't matter if target
# EXD file doesn't contain variables (0x02..0x03 segments).
$NEW_LINE = $UNIX_NEW_LINE
$BYTE_0 = [byte]0x30
$BYTE_x = [byte]0x78
$BYTE_CSV_SEPARATOR = [byte]0x7C  # Default is |
$BYTE_UNDERSCORE = [byte]0x5F
$ADD_SOURCE_TO_CSV = $true
$BIN_ADD_NEW_LINES = $false

# Doubling the CSV separator between Translation and Source in case there's this CSV separator inside actual string
$first_row = "Index$([char]$BYTE_CSV_SEPARATOR)Translation$([char]$BYTE_CSV_SEPARATOR)$([char]$BYTE_CSV_SEPARATOR)Source"
$first_row_bytes = [System.Text.Encoding]::UTF8.GetBytes($first_row)
foreach ($_byte in $first_row_bytes) {
    $null = $result_file.Add($_byte)
}
$null = $result_file.Add( $NEW_LINE )

for ($i = 0; $i -lt ($offset_table_size / 8); $i++)
{
    #$i = 6    # For debug - jump over specified number of offsets

    # Step 0. Get the start offset of data section and then from it the size of the current string
    $data_offset_byte = $exd_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
    $data_offset = [uint32](Convert-ByteArrayToHexString $data_offset_byte -Delimiter '' -Prepend '0x')
    $string_size_byte = $exd_bytes[$data_offset..($data_offset+3)]
    $string_size = [uint32](Convert-ByteArrayToHexString $string_size_byte -Delimiter '' -Prepend '0x')
    $source_data_offset_byte = $exd_source_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
    $source_data_offset = [uint32](Convert-ByteArrayToHexString $source_data_offset_byte -Delimiter '' -Prepend '0x')
    $source_string_size_byte = $exd_source_bytes[$source_data_offset..($source_data_offset+3)]
    $source_string_size = [uint32](Convert-ByteArrayToHexString $source_string_size_byte -Delimiter '' -Prepend '0x')
    
    # Step 1. Index
    # - Get an index in HEX form
    # - Add "0x" at the start of index in HEX form
    # - Write 0x<index_hex>| to the file
    # - Remove all zeroes (0x30) at the beginning of the index in HEX form
    # -- Add one if index_hex turned out to be empty (index == 0)
    $index_byte = $exd_bytes[(0x20+$i*0x8)..(0x23+$i*0x8)]
    [System.Collections.ArrayList]$index_hex = [System.Text.Encoding]::ASCII.GetBytes( $(Convert-ByteArrayToHexString $index_byte -Delimiter '') )
    $index = @( $BYTE_0, $BYTE_x ) + $index_hex
    foreach ($_byte in $index) {
        $null = $result_file.Add( $_byte )
    }
    $null = $result_file.Add( $BYTE_CSV_SEPARATOR )
    while ($index_hex[0] -eq $BYTE_0) {
        $index_hex.RemoveAt(0)
    }
    if ($null -eq $index_hex[0]) {
        $null = $index_hex.Add( [byte][char]"0" )
    }

    # Step 2. Source binary data
    # Note: since it's not intended to be edited and we have have data chunk size from EXH,
    # there's no need to make this file pretty. Therefore binary data goes in the file raw,
    # but feel free to uncomment new liner if you really want to.
    # - Get the data from the source EXD
    # - Write it as is
    # - (Optional) Add new line
    [System.Collections.ArrayList]$source_binary_byte = $exd_source_bytes[($source_data_offset+6)..($source_data_offset+5+$data_chunk_size)]
    foreach ($_byte in $source_binary_byte) {
        $null = $source_binary_file.Add( $_byte )
    }
    if ($BIN_ADD_NEW_LINES) {
        $null = $source_binary_file.Add( $NEW_LINE )
    }
    
    # Step 3. Translation string
    # - Get the translation string from target EXD
    # - Remove all 0x00 at the end of the string
    # - (Run-time choice) Write <index_hex>_ before the start of the string
    # - Write the translation string with CSV separator at the end
    [System.Collections.ArrayList]$string_bytes = $exd_bytes[($data_offset+6+$data_chunk_size)..($data_offset+5+$string_size)]
    for ($_j = $string_bytes.Count-1; $string_bytes[$_j] -eq [byte]0; $_j--) {
        $string_bytes.RemoveAt($_j)
    }
    if ($WRITE_INDEX_UNDERSCORE_IN_TRANSLATION) {
        foreach ($_byte in $index_hex) {
            $null = $result_file.Add( $_byte )
        }
        $null = $result_file.Add( $BYTE_UNDERSCORE )
    }
    foreach ($_byte in $string_bytes) {
        $null = $result_file.Add( $_byte )
    }
    $null = $result_file.Add( $BYTE_CSV_SEPARATOR )
    $null = $result_file.Add( $BYTE_CSV_SEPARATOR )
    
    # Step 4. Source string
    # - Get the source string from source EXD
    # - Remove all 0x00 at the end of the string
    # - Write the source string
    if ($ADD_SOURCE_TO_CSV) {
            [System.Collections.ArrayList]$source_string_bytes = $exd_source_bytes[($source_data_offset+6+$data_chunk_size)..($source_data_offset+5+$source_string_size)]
        for ($_j = $source_string_bytes.Count-1; $source_string_bytes[$_j] -eq [byte]0; $_j--) {
            $source_string_bytes.RemoveAt($_j)
        }
        foreach ($_byte in $source_string_bytes) {
            $null = $result_file.Add( $_byte )
        }
    }
    
    
    # Step 5. Add new line
    $null = $result_file.Add( $NEW_LINE )
}

if (($null -eq $result_file) -or ($null -eq $source_binary_file)) {
    "Something went wrong. Use IDE (e.g. PowerShell ISE) to debug"
    "or scroll up to read errors."
    Pause
    Return
}
Set-Content -Value $result_file -Encoding Byte -Path $csv_path
"$csv_path exported."
Set-Content -Value $source_binary_file -Encoding Byte -Path $bin_path
"$bin_path exported.`n"

}