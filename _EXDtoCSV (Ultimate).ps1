$host.UI.RawUI.WindowTitle = "EXD -> CSV (Ultimate)"

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

# String size will change, so this will keep track of how much
# and adjust values accordingly
$offset = 0

# Workaround variable to skip FFs.
# Case 1:
# There are several strings in addon_0_xx.exd with FE FF and
# FE FF FF FF FF structures. It seems like FE makes the game to
# ignore FFs for, I assume, 4 bytes. The purpose of those
# structures is unknown.
# Case 2:
# Need to address strings 0x2770 and 0x27B5 in addon_0_en.exd.
# Case 3:
# In a bunch of German and French files instead of writing
# item and NPC names as is, like in English and Japanese, they
# refer to them through variables of types 32 and 33. In result
# there's another FF after ((...)) so we're gonna ignore it too.
# TODO: Figure out how referencing works and make it more pretty.
$ignore_FF_counter = 0

for ($i = 0; $i -lt $input_string.Length; $i += 2) {
    while ( ($i -eq ($depth_memory[-1] + $offset)) -and $depth_memory[-1] ) {
        $depth_memory.RemoveAt($depth_memory.Count-1)
        switch ($type_byte) {
            '32' { $ignore_FF_counter = 1 } # Case 3
            '33' { $ignore_FF_counter = 1 } # Case 3
        }
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
                $ignore_FF_counter = 0 # Reset to avoid
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
                if ($type_byte -eq '49') { $ignore_FF_counter = 1 } # Case 2
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
            $ignore_FF_counter = 4   # Case 1
        } elseif ($input_string.Substring($i+2, 2) -eq 'FF') {
            $ignore_FF_counter = 2   # Case 1
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
        if ($byte_hex -eq 'FF' -and $ignore_FF_counter) { $ignore_FF_counter-- }
    }
}

$ByteArray = Convert-HexStringToByteArray $input_string
return $ByteArray
}


if (!$(Test-Path '.\current') ) {
    "Do you want $PWD to be your project translation folder? (Y/n)"
    $_answer = $(Read-Host "If so, 'current\exd_mod' and 'current\exh' folders will be created.").ToLower()
    switch ($_answer) {
        'n' { "Then move the script to the folder that contains 'current' folder."; pause; exit }
        default {
            New-Item '.\current' -ItemType Directory
            New-Item '.\current\exd_mod' -ItemType Directory
            New-Item '.\current\exh' -ItemType Directory
            break
        }
    }    
}

while ($true) {
    $SILENTLY_OVERWRITE = $false
    $GLOBAL_CUSTOMIZE = $false
    $current_dir = "$PWD\current"
    "Current project folder is $current_dir"
    "Put EXH files into .\current\exh"
    "and EXD files into .\current\exd_mod"
    "CSV files are expected to be in .\current\csv"
    "Drag and drop EXH, EXD, or CSV file and press Enter,"
    "or enter 'exh' to get all EXH files in current folder and subfolders,"
    "or enter 'csv' to get all CSV files in current folder and subfolders."
    $input_answer = Read-Host ' '
    if ( ($input_answer.ToLower() -eq 'exh') -or ($input_answer.ToLower() -eq 'csv') ) {
        if ($input_answer.ToLower() -eq 'exh') {
            $input_answer = Get-ChildItem ".\current\exh\*.exh" -Recurse
            "$($input_answer.Count) EXHs found."
        } else {
            $input_answer = Get-ChildItem ".\current\csv\*.csv" -Recurse
            "$($input_answer.Count) CSVs found."
        }
        $_answer = $(Read-Host "Do you want to overwrite all CSV files that already exist? (Y/n)").ToLower()
        switch ($_answer) {
            "n" { continue }
            default { $SILENTLY_OVERWRITE = $true }
        }
        "Do you want to make choices for all files right now?"
        $_answer = $(Read-Host "If not then you'll have to choose manually for each file. (Y/n)").ToLower()
        switch ($_answer) {
            "n" { continue }
            default {
                $GLOBAL_CUSTOMIZE = $true
                $_answer = $(Read-Host "Pre-fill translation strings? (y/N)").ToLower()
                switch ($_answer) {
                    "y" { $ADD_TRANSLATION_TO_CSV = $true; break }
                    default { $ADD_TRANSLATION_TO_CSV = $false; break }
                }
                if ($ADD_TRANSLATION_TO_CSV) {
                    $_answer = $(Read-Host "Add '<index>_' at the start of translation fields? (Y/n)").ToLower()
                    switch ($_answer) {
                        "n" { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $false; break }
                        default { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $true; break }
                    }
                }
            }
        }

        "Keep in mind that if there are several collections of EXDs for one EXH"
        "(e.g. languages) you'll be asked to choose one."
    } else {
        if ( $input_answer.StartsWith('"') -and $input_answer.EndsWith('"')) {
            $input_answer = $input_answer.Substring(1, $input_answer.Length-2)
        }
        if (!$(Test-Path $input_answer)) {
            "Input file wasn't found at $input_answer.`n"
            continue
        }
        $input_answer = Get-ChildItem $input_answer
    }

    foreach ($input_file in $input_answer) {
        switch ($input_file.Extension) {
            '.exh'  { $base_name = $input_file.BaseName; break }
            '.csv'  { $base_name = $input_file.BaseName; break }
            default { $base_name = [regex]::match( $input_file.BaseName,'.*(?=_\d_)').Groups[0].Value; break }
        }
        if (!$base_name) {
            "Base name of $($input_file.FullName) turned out empty. Skipping.`n"
            continue
        }
        $BIN_DIR          = "$current_dir\bin"
        $CSV_DIR          = "$current_dir\csv"
        $EXD_DIR          = "$current_dir\exd_mod"
        $EXD_SOURCE_DIR   = "$current_dir\exd_source"
        $EXH_DIR          = "$current_dir\exh"
        $SUB_PATH         = $input_file.FullName -replace '.*?\\bin|.*?\\csv|.*?\\exd_mod|.*?\\exd_source|.*?\\exh','' -replace "$($base_name).*",''

        # Get a nubmer of expected pages from EXH
        $exh_path = "$EXH_DIR$SUB_PATH$($base_name).exh"
        if (!$(Test-Path -Path $exh_path)) {
            "$($base_name): EXH file at $exh_path wasn't found."
            "$($base_name): Skipping.`n"
            continue
        }
        while ($true) {
            $exh_bytes = [System.IO.File]::ReadAllBytes($exh_path)
            if ($exh_bytes) { break }
            "$($base_name): Error while trying to read EXH file."
            "The file is probably locked by some program."
            $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
            if ($_answer -eq 'skip') { continue }
        }
        $number_of_pages = [uint32](Convert-ByteArrayToHexString $exh_bytes[0xA..0xB] -Delimiter '' -Prepend '0x')

        # Get all language EXD files that start with $base_name
        $exd_files = Get-ChildItem -Path "$EXD_DIR$SUB_PATH$($base_name)_*_*.exd" -Name
        if ($null -eq $exd_files) {
            "$($base_name): .exd file that has '$base_name' in its wasn't found."
            "If there's no language code at the end of the file name"
            "then this file is not language file and you shouldn't touch it.`n"
            continue
        }
        
        $options = New-Object System.Collections.ArrayList
        foreach ($exd_file in $exd_files) {
            $_file_ending = $exd_file -replace '.*\d_', ''
            if ( $options -notcontains $_file_ending ) {
                $null = $options.Add($_file_ending)
            }
        }
        if ($options.Count -gt 1) {
            "$($base_name): Several EXD collections were found:"
            "(A signle collection is determined by the ending of EXDs after the second _)"
            for ($_i = 0; $_i -lt $options.Count; $_i++) {
                switch ($options[$_i]) {
                    'en.exd' { "  $($_i+1). English (en.exd)"; break }
                    'fr.exd' { "  $($_i+1). French (fr.exd)"; break }
                    'de.exd' { "  $($_i+1). German (de.exd)"; break }
                    'ja.exd' { "  $($_i+1). Japanese (ja.exd)"; break }
                    default  { "  $($_i+1). $($options[$_i])"; break }
                }
            }
            "  0. Skip"
            $skip = $false
            while ($true) {
                $_choice = [int]$(Read-Host "Choose one")
                if ($_choice -eq 0) { $skip = $true; break }
                $_choice--
                if ( ($_choice -gt -1) -and ($_choice -lt $options.Count) ) {
                    $exd_files = Get-ChildItem -Path "$EXD_DIR$SUB_PATH$base_name*$($options[$_choice])"
                    if ($exd_files.Count -ne $number_of_pages) {
                        "$($base_name): There are $($exd_files.Count) files in selected EXD collection. Expected amount is $number_of_pages."
                    } else {
                        "$($base_name): $($options[$_choice]) collection was chosen."
                        break
                    }
                }
                "Try again."
            }
            if ($skip) { "$($base_name): Skipped"; continue }
        } else {
            "$($base_name): $($options[0]) collection was found."
            $exd_files = Get-ChildItem -Path "$EXD_DIR$SUB_PATH$base_name*$($options[0])"
        }
        $exd_files = $exd_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }

        # Setting up CSV path as $base_name.csv and asking questions about it
        $csv_path = "$CSV_DIR$SUB_PATH$base_name.csv"
        if (!$SILENTLY_OVERWRITE -and (Test-Path $csv_path)) {
            $_answer = $(Read-Host "$($base_name): $csv_path already exists. Overwrite? (Y/n)").ToLower()
            switch ($_answer) {
                "n" { continue }
                default { break }
            }
        }
        if (!$GLOBAL_CUSTOMIZE) {
            $_answer = $(Read-Host "Pre-fill translation strings? (y/N)").ToLower()
            switch ($_answer) {
                "y" { $ADD_TRANSLATION_TO_CSV = $true; break }
                default { $ADD_TRANSLATION_TO_CSV = $false; break }
            }
            if ($ADD_TRANSLATION_TO_CSV) {
                $_answer = $(Read-Host "Add '<index>_' at the start of translation fields? (Y/n)").ToLower()
                switch ($_answer) {
                    "n" { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $false; break }
                    default { $WRITE_INDEX_UNDERSCORE_IN_TRANSLATION = $true; break }
                }
            }
        }

        # Setting up directories for CSV, BIN, and source EXD files,
        # while also copying current EXDs as source if there are none in $EXD_SOURCE_DIR
        $exd_source_files = New-Object System.Collections.ArrayList
        foreach ($exd_file in $exd_files) {
            $null = $exd_source_files.Add("$EXD_SOURCE_DIR$SUB_PATH$($exd_file.BaseName).exd")
        }
        if (!$(Test-Path $(Split-Path $csv_path))) { New-Item $(Split-Path $csv_path) -ItemType Directory }
        if (!$(Test-Path "$BIN_DIR$SUB_PATH")) { New-Item "$BIN_DIR$SUB_PATH" -ItemType Directory }
        if (!$(Test-Path $(Split-Path $exd_source_files[0]))) { New-Item $(Split-Path $exd_source_files[0]) -ItemType Directory }
        for ($_i = 0; $_i -lt $exd_files.Count; $_i++) {
            if (!$(Test-Path $exd_source_files[$_i])) { Copy-Item $exd_files[$_i] $exd_source_files[$_i] }
        }

        $result_csv = New-Object System.Collections.ArrayList
        foreach ($exd_file in $exd_files) {
            while ($true) {
                $exd_bytes = [System.IO.File]::ReadAllBytes($exd_file.FullName)
                $exd_source_bytes = [System.IO.File]::ReadAllBytes( $exd_file.FullName.Replace("$EXD_DIR$SUBPATH", "$EXD_SOURCE_DIR$SUBPATH") )
                if ($exd_bytes -and $exd_source_bytes) { break }
                "$($base_name): Error while trying to read the following file(s):"
                if (!$exd_bytes) { $exd_file.FullName }
                if (!$exd_source_bytes) { $exd_file.FullName.Replace("$EXD_DIR$SUBPATH", "$EXD_SOURCE_DIR$SUBPATH") }
                "If they exist they are probably locked by some program."
                $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                if ($_answer -eq 'skip') { continue }
            }

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

            # Binary data will be put in a separate file.
            $bin_file = New-Object System.Collections.ArrayList

            $UNIX_NEW_LINE = [byte]0x0A
            $MAC_NEW_LINE = [byte]0x0D
            $COLUMN_SEPARATOR = '<tab>'
            $COLUMN_SEPARATOR_BYTE = [System.Text.Encoding]::UTF8.GetBytes($COLUMN_SEPARATOR)

            $NEW_LINE = @( $MAC_NEW_LINE, $UNIX_NEW_LINE)
            $BIN_ADD_NEW_LINES = $false

            $current_progress = 0
            $1_percent = $offset_table_size / 800
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
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
                $index_byte = $exd_bytes[(0x20+$i*0x8)..(0x23+$i*0x8)]
                $index_result = Convert-ByteArrayToHexString $index_byte -Delimiter '' -Prepend '0x'
            
                # Step 2. Source binary data
                # Note: since it's not intended to be edited and we have have data chunk size from EXH,
                # there's no need to make this file pretty. Therefore binary data goes in the file raw,
                # but feel free to uncomment the new liner if you really want/need to.
                # - Get the data from the source EXD
                # - Write it as is
                # - (Optional) Add new line
                [System.Collections.ArrayList]$bin_bytes = $exd_source_bytes[($source_data_offset+6)..($source_data_offset+5+$data_chunk_size)]
                foreach ($_byte in $bin_bytes) {
                    $null = $bin_file.Add( $_byte )
                }
                if ($BIN_ADD_NEW_LINES) {
                    foreach ($_byte in $NEW_LINE) {
                        $null = $bin_file.Add( $_byte )
                    }
                }
            
                # Step 3. Translation string (Run-time choice)
                # - Get the translation string from target EXD
                # - Change first <$number_of_string_datasets> 0x00 bytes to column separator
                # - Remove the rest of 0x00 bytes from the end of the string
                # - Change variables to more human-friendly format via my function
                # - (Run-time choice) Add <index_hex>_ at the start of the string
                if ($ADD_TRANSLATION_TO_CSV) {
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
                        $translation_result = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_bytes) )
                    } else {
                        $translation_result = [System.Text.Encoding]::UTF8.GetString($string_bytes)
                    }
                    if ($WRITE_INDEX_UNDERSCORE_IN_TRANSLATION) {
                        $index_hex = "{0:X}" -f [uint32]$index_result
                        $translation_result = "$($index_hex)_$translation_result"
                    }
                } else { $translation_result = "" }

                # Step 4. Source string
                # - Get the source string from source EXD
                # - Change first $number_of_string_datasets 0x00 bytes to column separator
                # - Remove the rest of 0x00 bytes from the end of the string
                # - Change variables to more human-friendly format via my function
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
                # See the comment about this 'if' above
                if ($source_string_bytes.Count -gt 3) {
                    $source_result = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $source_string_bytes) )
                } else {
                    $source_result = [System.Text.Encoding]::UTF8.GetString($source_string_bytes)
                }
            
                # Step 5. Compiling results into the future CSV file.
                $null = $result_csv.Add(
                    [PSCustomObject]@{
                        Index = $index_result
                        Translation = $translation_result
                        Source = $source_result
                    }
                )
            }
            Write-Progress -Activity "Converting EXD to CSV" -Completed
            $stopwatch.Stop()
            "$($exd_file.FullName) done in $($stopwatch.Elapsed.Seconds) s $($stopwatch.Elapsed.Milliseconds) ms"

            if ($null -eq $result_csv) {
                "Something went wrong. CSV turned out empty.`n"
                continue
            }
            if ($null -eq $bin_file) {
                "Something went wrong. Source binary file turned out empty.`n"
                continue
            }
            $bin_path = "$BIN_DIR$SUB_PATH$($exd_file.BaseName).bin"
            Set-Content -Value $bin_file -Encoding Byte -Path $bin_path
            "$bin_path exported."
        }
        $result_csv | Export-Csv -Path $csv_path -NoTypeInformation -Encoding UTF8
        "$csv_path exported.`n"
    }
    "Done.`n"
}