$host.UI.RawUI.WindowTitle = "EXD -> CSV (Unreal)"

# Function's source: https://www.sans.org/blog/powershell-byte-array-and-hex-functions/
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

# Function's source: https://www.sans.org/blog/powershell-byte-array-and-hex-functions/
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

# Following function was written by me
function Convert-VariablesToTags
{
################################################################
#.Synopsis
# Convert 0x02..0x03 variables in ByteArray into straight text.
# They will look like tags in result. Output is also ByteArray.
#.Parameter ByteArray
# System.Byte[] array of bytes of the target string.
#.Example
# [Byte[]] $x = 0x02,0x08,0x09,0xE9,0x05,0xFF,0x03,0xD0,0xB0,0xFF,0x01,0x03
# Convert-VariablesToTags $x
#
# <var 08 E905 ((а)) (()) /var>
################################################################
[CmdletBinding()] Param (
[Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Byte[]] $ByteArray
)
# It's much easier to operate with the string as an actual string so we're gonna convert it.
$input_string = Convert-ByteArrayToHexString $ByteArray -Delimiter '' -Width $ByteArray.Count
$depth_memory = [System.Collections.ArrayList]@()
$looking_for_02 = $true
$offset = 0    # String size is gonna change, so this will keep track of how much
               # and adjust values accordingly
$ignore_FF_counter = 0  # There are several strings in addon_0_xx.exd with FE FF and
                        # FE FF FF FF FF structures. It seems like FE makes the game to
                        # ignore FFs for, I assume, 4 bytes.

for ($i = 0; $i -lt $input_string.Length; $i += 2) {
    while ( ($i -eq ($depth_memory[-1] + $offset)) -and $depth_memory[-1] ) {
        $depth_memory.RemoveAt($depth_memory.Count-1)
        $byte = $input_string.Substring($i, 2)
        if ($byte -eq "03") {
            if ($looking_for_02) {
                $input_string = $input_string.Insert($i, "292920") # ")) "
                $offset += 6
                $i += 6
            } else {
                $input_string = $input_string.Remove($i, 2)
                $offset -= 2
                $previous_byte = $input_string.Substring($i-2, 2)
                if ($previous_byte -ne "20") {
                    $input_string = $input_string.Insert($i, "20") # " "
                    $offset += 2
                    $i += 2
                }
                $input_string = $input_string.Insert($i, "2F7661723E") # "/var>"
                $offset += 10
                $i += 10
            }
        } else {
            $input_string = $input_string.Insert($i, "292920") # ")) "
            $offset += 6
            $i += 6
        }
        $looking_for_02 = -not $looking_for_02
    }
    if ( $i+1 -gt $input_string.Length ) { break }
    if ( $looking_for_02 -and ($input_string.Substring($i, 2) -eq '0A') ) {
        $input_string = $input_string.Remove($i, 2).Insert($i, "3C6E6C3E") # "<nl>"
        $offset += 6
        $i += 6
    }
    if ( $looking_for_02 -and ($input_string.Substring($i, 2) -eq '02') ) { 
        $looking_for_02 = $false

        $type_byte = $input_string.Substring($i+2, 2)
        # TODO: Make these types dynamic by having a separate file with their definitions
        switch ($type_byte) {
            "10"    { $var_string = "3C62723E"; $skip_03 = $true; break } # <br> - New line
            default {
                $type_byte_hex = '{0:X2}{1:X2}' -f [uint32]$([System.Text.Encoding]::ASCII.GetBytes($type_byte.Substring(0,1))), [uint32]$([System.Text.Encoding]::ASCII.GetBytes($type_byte.Substring(1,1)))
                $var_string = "3C76617220$($type_byte_hex)20" # "<var XX " where XX is variable type
                $skip_03 = $false
                break }
        }

        $size_first_byte = $input_string.Substring($i+4, 2)
        switch ($size_first_byte) {
            "F2" {
                $size = [uint32]('0x' + $input_string.Substring($i+6, 4))
                $null = $depth_memory.Add( $i + ($size+5)*2 - $offset )
                $input_string = $input_string.Remove($i, 10).Insert($i, $var_string)
                $offset += $var_string.Length - 10
                break }
            "F1" {
                $size = [uint32]('0x' + $input_string.Substring($i+6, 2) + '00')
                $null = $depth_memory.Add( $i + ($size+4)*2 - $offset )
                $input_string = $input_string.Remove($i, 8).Insert($i, $var_string)
                $offset += $var_string.Length - 8
                break }
            "F0" {
                $size = [uint32]('0x' + $input_string.Substring($i+6, 2))
                $null = $depth_memory.Add( $i + ($size+4)*2 - $offset )
                $input_string = $input_string.Remove($i, 8).Insert($i, $var_string)
                $offset += $var_string.Length - 8
                break }
            default {
                if (-not $skip_03) {
                    $size = [uint32]('0x' + $size_first_byte) - 1
                    $null = $depth_memory.Add( $i + ($size+3)*2 - $offset )
                }
                if ($type_byte -eq '49') { $ignore_FF_counter = $size + 1 } # Temp. workaround, addressing 0x2770 and 0x27B5 in addon_0_en.exd
                $input_string = $input_string.Remove($i, 6).Insert($i, $var_string)
                $offset += $var_string.Length - 6
                break }
        }
        $i += $var_string.Length - 2
        if ($skip_03) {
            $input_string = $input_string.Remove($i+2, 2)
            $offset -= 2
            $looking_for_02 = $true
        }
        continue
    }
    if ( ($input_string.Substring($i, 2) -eq 'FF') -and -not $ignore_FF_counter) {
        if ($input_string.Substring($i-4, 4) -eq '4645') { # 'FE'
            $ignore_FF_counter = 4
        } elseif ($input_string.Substring($i+2, 2) -eq 'FF') {
            $ignore_FF_counter = 2
        } else {
            $looking_for_02 = $true
            
            $size_first_byte = $input_string.Substring($i+2, 2)
            switch ($size_first_byte) {
                "F2" {
                    $size = [uint32]('0x' + $input_string.Substring($i+4, 4))
                    $null = $depth_memory.Add( $i+8 + $size*2 - $offset )
                    $input_string = $input_string.Remove($i, 8)
                    $offset -= 8
                    break }
                "F1" {
                    $size = [uint32]('0x' + $input_string.Substring($i+4, 2) + '00')
                    $null = $depth_memory.Add( $i+6 + $size*2 - $offset )
                    $input_string = $input_string.Remove($i, 6)
                    $offset -= 6
                    break }
                "F0" {
                    $size = [uint32]('0x' + $input_string.Substring($i+4, 2))
                    $null = $depth_memory.Add( $i+6 + $size*2 - $offset )
                    $input_string = $input_string.Remove($i, 6)
                    $offset -= 6
                    break }
                default {
                    $size = [uint32]('0x' + $size_first_byte) - 1
                    $null = $depth_memory.Add( $i+4 + $size*2 - $offset )
                    $input_string = $input_string.Remove($i, 4)
                    $offset -= 4
                    break }
            }

            $previous_byte = $input_string.Substring($i-2, 2)
            if ($previous_byte -ne "20") {
                $input_string = $input_string.Insert($i, "20") # " "
                $offset += 2
                $i += 2
            }
            $input_string = $input_string.Insert($i, "2828") # "(("
            $offset += 4
            $i += 2

            continue
        }
    }
    if (-not $looking_for_02) {
        $byte = $input_string.Substring($i, 2)
        $byte_hex = '{0:X2}{1:X2}' -f [uint32]$([System.Text.Encoding]::ASCII.GetBytes($byte.Substring(0,1))), [uint32]$([System.Text.Encoding]::ASCII.GetBytes($byte.Substring(1,1)))
        $input_string = $input_string.Remove($i, 2).Insert($i, "$($byte_hex)")
        $offset += 2
        $i += 2
        if ($ignore_FF_counter) { $ignore_FF_counter-- }
    }
}

$ByteArray = Convert-HexStringToByteArray $input_string
return $ByteArray
}


while ($true) {

$SILENTLY_OVERWRITE = $false
$GLOBAL_CUSTOMIZE = $false
"Drag and drop EXH file and press Enter,"
"or enter 'all' to get all EXH files in current folder."
$exh_answer = Read-Host ' '
if ($exh_answer.ToLower() -eq 'all') {
    $_answer = $(Read-Host "Do you want to overwrite all CSV files that already exist? (Y/n)").ToLower()
    switch ($_answer) {
        "n" { continue }
        default { $SILENTLY_OVERWRITE = $true }
    }
    $_answer = $(Read-Host "Do you want to make choices for all files right now?`nIf not then you'll have to choose manually for each file. (Y/n)").ToLower()
    switch ($_answer) {
        "n" { continue }
        default {
            $GLOBAL_CUSTOMIZE = $true
            $_answer = $(Read-Host "Add '<index>_' at the start of translation fields? (y/N)").ToLower()
            switch ($_answer) {
                "y" { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $true; break }
                default { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $false; break }
            }
            $_answer = $(Read-Host "Add source strings? (Y/n)").ToLower()
            switch ($_answer) {
                "n" { $ADD_SOURCE_TO_CSV = $false; break }
                default { $ADD_SOURCE_TO_CSV = $true; break }
            }
        }
    }
    
    "Keep in mind that if there are several EXDs for one EXH, you'll be asked to choose one."
    $exh_answer = Get-ChildItem ".\*.exh"
    "$($exh_answer.Count) EXHs found."
} else {
    if ( $exh_answer.StartsWith('"') -and $exh_answer.EndsWith('"')) {
        $exh_answer = $exh_answer.Substring(1, $exh_answer.Length-2)
    }
    if (!$(Test-Path $exh_answer)) {
        "EXH file wasn't found at $exh_answer.`n"
        continue
    }
    $exh_answer = Get-ChildItem $exh_answer
}

foreach ($exh_path in $exh_answer) {

$exh_file_name = $exh_path.BaseName
$current_dir = $exh_path.Directory.FullName
$exh_path = $exh_path.FullName
$EXD_DIR          = "$current_dir"
$BIN_DIR          = "$current_dir\bin"
$CSV_DIR          = "$current_dir\csv"
$EXD_SOURCE_DIR   = "$current_dir\source"

$exd_files = Get-ChildItem -Path "$EXD_DIR\$($exh_file_name)_*_*.exd" -Name
$exd_path = "$EXD_DIR\"
if ($null -eq $exd_files) {
    "$($exh_file_name): Suitable .exd file with the name `"$exh_file_name`" wasn't found."
    "If there's no language code at the end of the file name"
    "then this file is not language file and you shouldn't touch it.`n"
    continue
}
if ($exd_files.Count -gt 1) {
    "$($exh_file_name): Several EXD files were found:"
    for ($_i = 0; $_i -lt $exd_files.Count; $_i++) {
        "  $($_i+1). $($exd_files[$_i])"
    }
    "  0. Skip file"
    $skip = $false
    while ($true) {
        $_choice = [int]$(Read-Host "Choose one")
        if ($_choice -eq 0) { $skip = $true; break }
        $_choice--
        if ( ($_choice -gt -1) -and ($_choice -lt $exd_files.Count) ) {
            "$($exd_files[$_choice]) was chosen."
            $exd_path += $exd_files[$_choice]
            break
        }
        "Try again."
    }
    if ($skip) { "$($exh_file_name): Skipped"; continue }
} else {
    "$($exh_file_name): $exd_files was found."
    $exd_path += $exd_files
}
$exd_file_name = $(Split-Path $exd_path -Leaf).TrimEnd(".exd")

$csv_path = "$CSV_DIR\$exd_file_name.csv"
if (!$SILENTLY_OVERWRITE -and (Test-Path $csv_path)) {
    $_answer = $(Read-Host "$($exh_file_name): $csv_path already exists. Overwrite? (Y/n)").ToLower()
    switch ($_answer) {
        "n" { continue }
        default { break }
    }
}
if (!$GLOBAL_CUSTOMIZE) {
    $_answer = $(Read-Host "$($exh_file_name): Add '<index>_' at the start of translation fields? (y/N)").ToLower()
    switch ($_answer) {
        "y" { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $true; break }
        default { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $false; break }
    }
    $_answer = $(Read-Host "$($exh_file_name): Add source strings? (Y/n)").ToLower()
    switch ($_answer) {
        "n" { $ADD_SOURCE_TO_CSV = $false; break }
        default { $ADD_SOURCE_TO_CSV = $true; break }
    }
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
    "$($exh_file_name): Error while trying to read either EXH, or EXD (or both)."
    "The file(s) is/are probably locked by some program."
    $null = Read-Host "Press Enter when you're ready to try again."
}
"EXD to CSV conversion is in process..."

$data_chunk_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x6..0x7] -Delimiter '' -Prepend '0x')
$number_of_datasets = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x8..0x9] -Delimiter '' -Prepend '0x')
$number_of_string_datasets = 0
for ($i = 0; $i -lt $number_of_datasets; $i++) {
    if (-not $(Compare-Object $exh_bytes[(0x20+$i*4)..(0x20+$i*4+1)] @( [byte]0, [byte]0 ) -SyncWindow 0) ) {
        $number_of_string_datasets++
    }
}
$offset_table_size = [uint32](Convert-ByteArrayToHexString $exd_bytes[0x8..0xB] -Delimiter '' -Prepend '0x')
# $data_section_size = [uint32](Convert-ByteArrayToHexString $exd_bytes[0xC..0xF] -Delimiter '' -Prepend '0x')

# To avoid wack UTF-8 encoding of Windows PowerShell we'll be working directly with bytes instead.
# The following loop will build the resulting CSV block by block.
$result_file = New-Object System.Collections.ArrayList
# Binary data will be put in a separate file.
$source_binary_file = New-Object System.Collections.ArrayList

$UNIX_NEW_LINE = [byte]0x0A
$MAC_NEW_LINE = [byte]0x0D
$0_BYTE = [byte]0x30
$UNDERSCORE_BYTE = [byte]0x5F
$x_BYTE = [byte]0x78
# If you're going to change the separator, make sure the script file is in UTF-8 BOM
$CSV_SEPARATOR = '┃'
$CSV_SEPARATOR_BYTE = [System.Text.Encoding]::UTF8.GetBytes($CSV_SEPARATOR)
$COLUMN_SEPARATOR = '<tab>'
$COLUMN_SEPARATOR_BYTE = [System.Text.Encoding]::UTF8.GetBytes($COLUMN_SEPARATOR)

$NEW_LINE = @( $MAC_NEW_LINE, $UNIX_NEW_LINE)
$BIN_ADD_NEW_LINES = $false

$first_row = "Index$($CSV_SEPARATOR)Translation$($CSV_SEPARATOR)Source"
$first_row_bytes = [System.Text.Encoding]::UTF8.GetBytes($first_row) # Same as above, make sure the conversion works right
foreach ($_byte in $first_row_bytes) {
    $null = $result_file.Add($_byte)
}
foreach ($_byte in $NEW_LINE) {
    $null = $result_file.Add( $_byte )
}

$current_progress = 0
$1_percent = $offset_table_size / 800
for ($i = 0; $i -lt ($offset_table_size / 8); $i++)
{
    if ( $i -gt ($1_percent * $current_progress) ) {
        $current_progress += 1
        Write-Progress -Activity "Converting EXD to CSV" -Status "$current_progress% Complete:" -PercentComplete $current_progress
    }
    #$i = 7484  # Debug - jump to specified offset
    #$i         # Debug - output current offset

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
    $index = @( $0_BYTE, $x_BYTE ) + $index_hex
    foreach ($_byte in $index) {
        $null = $result_file.Add( $_byte )
    }
    foreach ($_byte in $CSV_SEPARATOR_BYTE) {
        $null = $result_file.Add( $_byte )
    }
    while ($index_hex[0] -eq $0_BYTE) {
        $index_hex.RemoveAt(0)
    }
    if ($null -eq $index_hex[0]) {
        $null = $index_hex.Add( $0_BYTE )
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
        foreach ($_byte in $NEW_LINE) {
            $null = $source_binary_file.Add( $_byte )
        }
    }

    # Step 3. Translation string
    # - Get the translation string from target EXD
    # - Change first <$number_of_string_datasets> 0x00 bytes to column separator
    # - Remove the rest of 0x00 bytes from the end of the string
    # - Change variables to more human-friendly format via my function
    # - (Run-time choice) Write <index_hex>_ at the start of the string
    # - Write the translation string with CSV separator at the end
    [System.Collections.ArrayList]$string_bytes = $exd_bytes[($data_offset+6+$data_chunk_size)..($data_offset+5+$string_size)]
    $_change_to_column_separator_counter = $number_of_string_datasets - 1
    for ($_j = 0; $_j -lt $string_bytes.Count; $_j++) {
        if ( ($string_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
            $string_bytes.RemoveAt($_j)
            foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                $string_bytes.Insert($_j, $_byte)
                $_j++
            }
            $_j--
            $_change_to_column_separator_counter--
        }
    }
    for ($_j = $string_bytes.Count-1; $string_bytes[$_j] -eq [byte]0x00; $_j--) {
        $string_bytes.RemoveAt($_j)
    }
    # There's no point to go through the script for small strings that
    # will not have a variable, so we'll assume that the smallest possible
    # variable is 02 10 01 03 (<br>) which is 4 bytes long.
    if ($string_bytes.Count -gt 3) {
        [System.Collections.ArrayList]$string_bytes = Convert-VariablesToTags $string_bytes
    }
    if ($WRITE_INDEX_UNDERSCORE_IN_TRANSLATION) {
        foreach ($_byte in $index_hex) {
            $null = $result_file.Add( $_byte )
        }
        $null = $result_file.Add( $UNDERSCORE_BYTE )
    }
    foreach ($_byte in $string_bytes) {
        $null = $result_file.Add( $_byte )
    }
    foreach ($_byte in $CSV_SEPARATOR_BYTE) {
        $null = $result_file.Add( $_byte )
    }
    
    # Step 4. Source string (Run-time choice)
    # - Get the source string from source EXD
    # - Change first <$number_of_string_datasets> 0x00 bytes to column separator
    # - Remove the rest of 0x00 bytes from the end of the string
    # - Change variables to more human-friendly format via the function
    # - Write the source string
    if ($ADD_SOURCE_TO_CSV) {
        [System.Collections.ArrayList]$source_string_bytes = $exd_source_bytes[($source_data_offset+6+$data_chunk_size)..($source_data_offset+5+$source_string_size)]
        $_change_to_column_separator_counter = $number_of_string_datasets - 1
        for ($_j = 0; $_j -lt $source_string_bytes.Count; $_j++) {
            if ( ($source_string_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                $source_string_bytes.RemoveAt($_j)
                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                    $source_string_bytes.Insert($_j, $_byte)
                    $_j++
                }
                $_j--
                $_change_to_column_separator_counter--
            }
        }
        for ($_j = $source_string_bytes.Count-1; $source_string_bytes[$_j] -eq [byte]0; $_j--) {
            $source_string_bytes.RemoveAt($_j)
        }
        # See the comment about it above
        if ($source_string_bytes.Count -gt 3) {
            [System.Collections.ArrayList]$source_string_bytes = Convert-VariablesToTags $source_string_bytes
        }
        foreach ($_byte in $source_string_bytes) {
            $null = $result_file.Add( $_byte )
        }
    }
    
    # Step 5. Add new line
    foreach ($_byte in $NEW_LINE) {
        $null = $result_file.Add( $_byte )
    }
}
Write-Progress -Activity "Converting EXD to CSV" -Completed

if ($null -eq $result_file) {
    "Something went wrong. CSV turned out empty.`n"
    continue
}
if ($null -eq $source_binary_file) {
    "Something went wrong. Source binary file turned out empty.`n"
    continue
}
Set-Content -Value $result_file -Encoding Byte -Path $csv_path
"$csv_path exported."
Set-Content -Value $source_binary_file -Encoding Byte -Path $bin_path
"$bin_path exported.`n"
}

}