$host.UI.RawUI.WindowTitle = "EXD -> CSV (Ultimate) - Weblate"

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
    $SILENTLY_OVERWRITE_RUS = $false
    $GLOBAL_CUSTOMIZE = $false
    $current_dir = "$PWD\current"
    "Current project folder is $current_dir"
    "Put EXH files into .\current\exh (required),"
    "source EXD files into .\current\exd_source (at least EN required),"
    "and modded EXD files into .\current\exd_mod_ru and/or .\current\exd_mod_ruen"
    "CSV files are expected to be in .\current\csv"
    "Drag and drop EXH, EXD, or CSV file and press Enter,"
    "or enter 'exh' to get all EXH files in current folder and subfolders,"
    "or enter 'csv' to get all RUS CSV files in current folder and subfolders."
    $input_answer = Read-Host ' '
    if ( ($input_answer.ToLower() -eq 'exh') -or ($input_answer.ToLower() -eq 'csv') ) {
        if ($input_answer.ToLower() -eq 'exh') {
            $input_answer = Get-ChildItem ".\current\*.exh" -Recurse
            "$($input_answer.Count) EXHs found."
        } else {
            $input_answer = Get-ChildItem ".\current\csv\*\ru.csv" -Recurse
            "$($input_answer.Count) CSVs found."
        }
        $_answer = $(Read-Host "Do you want to overwrite all RU/RUEN CSV files that already exist? (Y/n)").ToLower()
        switch ($_answer) {
            "n" { continue }
            default { $SILENTLY_OVERWRITE_RUS = $true }
        }
        "Note: Source CSVs will not be overwritten if found. Delete them if you want to recreate."
        "Do you want to make choices for all files right now?"
        $_answer = $(Read-Host "If not then you'll have to choose manually for each file. (Y/n)").ToLower()
        switch ($_answer) {
            "n" { continue }
            default {
                $GLOBAL_CUSTOMIZE = $true
                $_answer = $(Read-Host "Create RUS and RUEN CSVs? (Y/n)").ToLower()
                switch ($_answer) {
                    "n" { $CREATE_RUS_RUEN_CSVs = $false; break }
                    default { $CREATE_RUS_RUEN_CSVs = $true; break }
                }
                if ($CREATE_RUS_RUEN_CSVs) {
                    $_answer = $(Read-Host "Add '<index>_' at the start of target fields? (y/N)").ToLower()
                    switch ($_answer) {
                        "y" { $WRITE_INDEX_UNDERSCORE_IN_TARGET = $true; break }
                        default { $WRITE_INDEX_UNDERSCORE_IN_TARGET = $false; break }
                    }
                }
                }
        }
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
            '.csv'  { $base_name = $input_file.Directory.Name; break }
            default { $base_name = [regex]::match( $input_file.BaseName,'.*(?=_\d_)').Groups[0].Value; break }
        }
        if (!$base_name) {
            "Base name of $($input_file.FullName) turned out empty. Skipping.`n"
            continue
        }
        $BIN_DIR          = "$current_dir\bin"
        $CSV_DIR          = "$current_dir\csv"
        $EXD_MOD_DIR_RU   = "$current_dir\exd_mod_ru"
        $EXD_MOD_DIR_RUEN = "$current_dir\exd_mod_ruen"
        $EXD_SOURCE_DIR   = "$current_dir\exd_source"
        $EXH_DIR          = "$current_dir\exh"
        $SUB_PATH         = $input_file.FullName -replace '.*?\\bin|.*?\\csv|.*?\\exd_mod_ru|.*?\\exd_mod_ruen|.*?\\exd_source|.*?\\exh','' -replace "$($base_name).*",''

        # Get info about pages from EXH
        if (Test-Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name).exh") {
            if (!$(Test-Path "$EXH_DIR$SUB_PATH")) { $null = New-Item "$EXH_DIR$SUB_PATH" -ItemType Directory }
            Move-Item "$EXD_SOURCE_DIR$SUB_PATH$($base_name).exh" "$EXH_DIR$SUB_PATH$($base_name).exh" -Force
            "$($base_name): EXH file was found in 'exd_source' - moved it to 'exh' folder."
        }
        $exh_path = "$EXH_DIR$SUB_PATH$($base_name).exh"
        if (!$(Test-Path -Path $exh_path)) {
            "$($base_name): EXH file at $exh_path wasn't found. Skipping.`n"
            continue
        } else { "$($base_name): EXH file found at $exh_path." }
        while ($true) {
            $exh_bytes = [System.IO.File]::ReadAllBytes($exh_path)
            if ($exh_bytes) { break }
            "$($base_name): Error while trying to read EXH file."
            "The file is probably locked by some program."
            $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
            if ($_answer -eq 'skip') { "$($base_name): Skipping.`n"; continue }
        }
        $number_of_datasets = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x8..0x9] -Delimiter '' -Prepend '0x')
        $number_of_pages = [uint32](Convert-ByteArrayToHexString $exh_bytes[0xA..0xB] -Delimiter '' -Prepend '0x')
        $page_table = New-Object System.Collections.ArrayList
        for ($_i = 0; $_i -lt $number_of_pages; $_i++) {
            $_offset = 0x20 + $number_of_datasets * 4 + $_i * 8
            $_page_entry = [uint32](Convert-ByteArrayToHexString $exh_bytes[$_offset..($_offset+3)] -Delimiter '' -Prepend '0x')
            $_page_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[($_offset+4)..($_offset+7)] -Delimiter '' -Prepend '0x')
            $null = $page_table.Add( @{ PageEntry = $_page_entry; PageSize = $_page_size } )
        }

        # Set up CSV and EXD paths for all languages
        $first_page = $page_table[0].PageEntry
        # Source section
        $csv_en_path = "$CSV_DIR$SUB_PATH$base_name\en.csv"
        $csv_de_path = "$CSV_DIR$SUB_PATH$base_name\de.csv"
        $csv_fr_path = "$CSV_DIR$SUB_PATH$base_name\fr.csv"
        $csv_ja_path = "$CSV_DIR$SUB_PATH$base_name\ja.csv"
        $CREATE_SOURCE_EN = $false
        $CREATE_SOURCE_DE = $false
        $CREATE_SOURCE_FR = $false
        $CREATE_SOURCE_JA = $false
        $exd_en_files = Get-ChildItem -Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_*_en.exd"
        if ($exd_en_files.Count -ne $number_of_pages) {
            "$($base_name): EN source EXDs were found but incorrect number of pages. ($($exd_en_files.Count) instead of $number_of_pages)"
            "This is critical since EN is considered 'source of sources' and thus required. Skipping.`n"
            continue
        }
        $exd_en_files = $exd_en_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
        if ( !$(Test-Path $csv_en_path) ) { $CREATE_SOURCE_EN = $true }
        if ( !$(Test-Path $csv_de_path) -and $(Test-Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_$($first_page)_de.exd") ) {
            $exd_de_files = Get-ChildItem -Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_*_de.exd"
            if ($exd_de_files.Count -eq $number_of_pages) {
                $CREATE_SOURCE_DE = $true
                $exd_de_files = $exd_de_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
            } else { "$($base_name): DE source EXDs were found but incorrect number of pages. ($($exd_de_files.Count) instead of $number_of_pages)" }
        }
        if ( !$(Test-Path $csv_fr_path) -and $(Test-Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_$($first_page)_fr.exd") ) {
            $exd_fr_files = Get-ChildItem -Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_*_fr.exd"
            if ($exd_fr_files.Count -eq $number_of_pages) {
                $CREATE_SOURCE_FR = $true
                $exd_fr_files = $exd_fr_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
            } else { "$($base_name): FR source EXDs were found but incorrect number of pages. ($($exd_fr_files.Count) instead of $number_of_pages)" }
        }
        if ( !$(Test-Path $csv_ja_path) -and $(Test-Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_$($first_page)_ja.exd") ) {
            $exd_ja_files = Get-ChildItem -Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name)_*_ja.exd"
            if ($exd_ja_files.Count -eq $number_of_pages) {
                $CREATE_SOURCE_JA = $true
                $exd_ja_files = $exd_ja_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
            } else { "$($base_name): JA source EXDs were found but incorrect number of pages. ($($exd_ja_files.Count) instead of $number_of_pages)" }
        }

        # Target CSVs questions
        if (!$GLOBAL_CUSTOMIZE) {
            $_answer = $(Read-Host "Create RUS and RUEN CSVs? (Y/n)").ToLower()
            switch ($_answer) {
                "n" { $CREATE_RUS_RUEN_CSVs = $false; break }
                default { $CREATE_RUS_RUEN_CSVs = $true; break }
            }
            if ($CREATE_RUS_RUEN_CSVs) {
                $_answer = $(Read-Host "Add '<index>_' at the start of target fields? (y/N)").ToLower()
                switch ($_answer) {
                    "y" { $WRITE_INDEX_UNDERSCORE_IN_TARGET = $true; break }
                    default { $WRITE_INDEX_UNDERSCORE_IN_TARGET = $false; break }
                }
            }
        }
        # Target section
        # TODO: Automatic detection of any non-source language?
        $CREATE_TARGET_RU = $false
        $CREATE_TARGET_RUEN = $false
        if ($CREATE_RUS_RUEN_CSVs) {
            $csv_ru_path = "$CSV_DIR$SUB_PATH$base_name\ru.csv"
            $csv_ruen_path = "$CSV_DIR$SUB_PATH$base_name\ruen.csv"
            if ( !$(Test-Path $csv_ru_path) -and $(Test-Path "$EXD_MOD_DIR_RU$SUB_PATH$($base_name)_$($first_page)_en.exd") ) {
                $exd_ru_files = Get-ChildItem -Path "$EXD_MOD_DIR_RU$SUB_PATH$($base_name)_*_en.exd"
                if ($exd_ru_files.Count -eq $number_of_pages) {
                    $CREATE_TARGET_RU = $true
                    $exd_ru_files = $exd_ru_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
                } else { "$($base_name): RU source EXDs were found but incorrect number of pages. ($($exd_ru_files.Count) instead of $number_of_pages)" }
            }
            if ( !$(Test-Path $csv_ruen_path) -and $(Test-Path "$EXD_MOD_DIR_RUEN$SUB_PATH$($base_name)_$($first_page)_en.exd") ) {
                $exd_ruen_files = Get-ChildItem -Path "$EXD_MOD_DIR_RUEN$SUB_PATH$($base_name)_*_en.exd"
                if ($exd_ruen_files.Count -eq $number_of_pages) {
                    $CREATE_TARGET_RUEN = $true
                    $exd_ruen_files = $exd_ruen_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
                } else { "$($base_name): RUEN source EXDs were found but incorrect number of pages. ($($exd_ruen_files.Count) instead of $number_of_pages)" }
            }
        }

        if (!$(Test-Path "$CSV_DIR$SUB_PATH$base_name")) { New-Item "$CSV_DIR$SUB_PATH$base_name" -ItemType Directory }
        if (!$(Test-Path "$BIN_DIR$SUB_PATH")) { New-Item "$BIN_DIR$SUB_PATH" -ItemType Directory }

        # Create CSV variables for all languages
        if ($CREATE_SOURCE_EN)   { $csv_en = New-Object System.Collections.ArrayList }
        if ($CREATE_SOURCE_DE)   { $csv_de = New-Object System.Collections.ArrayList }
        if ($CREATE_SOURCE_FR)   { $csv_fr = New-Object System.Collections.ArrayList }
        if ($CREATE_SOURCE_JA)   { $csv_ja = New-Object System.Collections.ArrayList }
        if ($CREATE_TARGET_RU)   { $csv_ru = New-Object System.Collections.ArrayList }
        if ($CREATE_TARGET_RUEN) { $csv_ruen = New-Object System.Collections.ArrayList }

        if ($CREATE_SOURCE_EN -or $CREATE_SOURCE_DE -or $CREATE_SOURCE_FR -or $CREATE_SOURCE_JA -or $CREATE_TARGET_RU -or $CREATE_TARGET_RUEN) {
            for ($_page = 0; $_page -lt $number_of_pages; $_page++) {
                while ($true) {
                    $exd_en_bytes = [System.IO.File]::ReadAllBytes($exd_en_files[$_page].FullName)
                    if ($CREATE_SOURCE_DE)   { $exd_de_bytes = [System.IO.File]::ReadAllBytes($exd_de_files[$_page].FullName) }
                    if ($CREATE_SOURCE_FR)   { $exd_fr_bytes = [System.IO.File]::ReadAllBytes($exd_fr_files[$_page].FullName) }
                    if ($CREATE_SOURCE_JA)   { $exd_ja_bytes = [System.IO.File]::ReadAllBytes($exd_ja_files[$_page].FullName) }
                    if ($CREATE_TARGET_RU)   { $exd_ru_bytes = [System.IO.File]::ReadAllBytes($exd_ru_files[$_page].FullName) }
                    if ($CREATE_TARGET_RUEN) { $exd_ruen_bytes = [System.IO.File]::ReadAllBytes($exd_ruen_files[$_page].FullName) }
                    if ( $exd_en_bytes -and
                        (!$CREATE_SOURCE_DE -or $exd_de_bytes) -and
                        (!$CREATE_SOURCE_FR -or $exd_fr_bytes) -and
                        (!$CREATE_SOURCE_JA -or $exd_ja_bytes) -and
                        (!$CREATE_TARGET_RU -or $exd_ru_bytes) -and
                        (!$CREATE_TARGET_RUEN -or $exd_ruen_bytes) ) { break }
                    "$($base_name): Error while trying to read the following file(s):"
                    if ( !$exd_en_bytes ) { $exd_en_files[$_page].FullName }
                    if ($CREATE_SOURCE_DE -and !$exd_de_files) { $exd_de_files[$_page].FullName }
                    if ($CREATE_SOURCE_FR -and !$exd_fr_files) { $exd_fr_files[$_page].FullName }
                    if ($CREATE_SOURCE_JA -and !$exd_ja_files) { $exd_ja_files[$_page].FullName }
                    if ($CREATE_TARGET_RU -and !$exd_ru_files) { $exd_ru_files[$_page].FullName }
                    if ($CREATE_TARGET_RUEN -and !$exd_ruen_files) { $exd_ruen_files[$_page].FullName }
                    "If they exist they are probably locked by some program."
                    $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                    if ($_answer -eq 'skip') { continue }
                }

                $data_chunk_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x6..0x7] -Delimiter '' -Prepend '0x')
                $number_of_string_datasets = 0
                for ($i = 0; $i -lt $number_of_datasets; $i++) {
                    if (-not $(Compare-Object $exh_bytes[(0x20+$i*4)..(0x20+$i*4+1)] @( [byte]0, [byte]0 ) -SyncWindow 0) ) {
                        $number_of_string_datasets++
                    }
                }

                $offset_table_size = [uint32](Convert-ByteArrayToHexString $exd_en_bytes[0x8..0xB] -Delimiter '' -Prepend '0x')   # Same for all languages
                # $data_section_size = [uint32](Convert-ByteArrayToHexString $exd_en_bytes[0xC..0xF] -Delimiter '' -Prepend '0x')

                # Binary data will be put in a separate file (only from EN)
                $bin_en_file = New-Object System.Collections.ArrayList

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
                    $data_offset_en_byte = $exd_en_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                    $data_offset_en = [uint32](Convert-ByteArrayToHexString $data_offset_en_byte -Delimiter '' -Prepend '0x')
                    $string_size_en_byte = $exd_en_bytes[$data_offset_en..($data_offset_en+3)]
                    $string_size_en = [uint32](Convert-ByteArrayToHexString $string_size_en_byte -Delimiter '' -Prepend '0x')
                    if ($CREATE_SOURCE_DE) {
                        $data_offset_de_byte = $exd_de_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                        $data_offset_de = [uint32](Convert-ByteArrayToHexString $data_offset_de_byte -Delimiter '' -Prepend '0x')
                        $string_size_de_byte = $exd_de_bytes[$data_offset_de..($data_offset_de+3)]
                        $string_size_de = [uint32](Convert-ByteArrayToHexString $string_size_de_byte -Delimiter '' -Prepend '0x')
                    }
                    if ($CREATE_SOURCE_FR) {
                        $data_offset_fr_byte = $exd_fr_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                        $data_offset_fr = [uint32](Convert-ByteArrayToHexString $data_offset_fr_byte -Delimiter '' -Prepend '0x')
                        $string_size_fr_byte = $exd_fr_bytes[$data_offset_fr..($data_offset_fr+3)]
                        $string_size_fr = [uint32](Convert-ByteArrayToHexString $string_size_fr_byte -Delimiter '' -Prepend '0x')
                    }
                    if ($CREATE_SOURCE_JA) {
                        $data_offset_ja_byte = $exd_ja_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                        $data_offset_ja = [uint32](Convert-ByteArrayToHexString $data_offset_ja_byte -Delimiter '' -Prepend '0x')
                        $string_size_ja_byte = $exd_ja_bytes[$data_offset_ja..($data_offset_ja+3)]
                        $string_size_ja = [uint32](Convert-ByteArrayToHexString $string_size_ja_byte -Delimiter '' -Prepend '0x')
                    }
                    if ($CREATE_TARGET_RU) {
                        $data_offset_ru_byte = $exd_ru_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                        $data_offset_ru = [uint32](Convert-ByteArrayToHexString $data_offset_ru_byte -Delimiter '' -Prepend '0x')
                        $string_size_ru_byte = $exd_ru_bytes[$data_offset_ru..($data_offset_ru+3)]
                        $string_size_ru = [uint32](Convert-ByteArrayToHexString $string_size_ru_byte -Delimiter '' -Prepend '0x')
                    }
                    if ($CREATE_TARGET_RUEN) {
                        $data_offset_ruen_byte = $exd_ruen_bytes[(0x24+$i*0x8)..(0x27+$i*0x8)]
                        $data_offset_ruen = [uint32](Convert-ByteArrayToHexString $data_offset_ruen_byte -Delimiter '' -Prepend '0x')
                        $string_size_ruen_byte = $exd_ruen_bytes[$data_offset_ruen..($data_offset_ruen+3)]
                        $string_size_ruen = [uint32](Convert-ByteArrayToHexString $string_size_ruen_byte -Delimiter '' -Prepend '0x')
                    }

                    # Step 1. Index
                    # - Get an index in HEX form
                    $index_byte = $exd_en_bytes[(0x20+$i*0x8)..(0x23+$i*0x8)]
                    $index_result = Convert-ByteArrayToHexString $index_byte -Delimiter '' -Prepend '0x'
                
                    # Step 2. Source binary data
                    # Note: since it's not intended to be edited and we have have data chunk size from EXH,
                    # there's no need to make this file pretty. Therefore binary data goes in the file raw,
                    # but feel free to uncomment the new liner if you really want/need to.
                    # - Get the data from the source EXD
                    # - Write it as is
                    # - (Optional) Add new line
                    [System.Collections.ArrayList]$bin_en_bytes = $exd_en_bytes[($data_offset_en+6)..($data_offset_en+5+$data_chunk_size)]
                    foreach ($_byte in $bin_en_bytes) {
                        $null = $bin_en_file.Add( $_byte )
                    }
                    if ($BIN_ADD_NEW_LINES) {
                        foreach ($_byte in $NEW_LINE) {
                            $null = $bin_en_file.Add( $_byte )
                        }
                    }
                
                    # Step 3. EN strings (and CSV if it doesn't exist)
                    # - Get the source string from source EXD
                    # - Change first $number_of_string_datasets 0x00 bytes to column separator
                    # - Remove the rest of 0x00 bytes from the end of the string
                    # - Change variables to more human-friendly format via my function
                    [System.Collections.ArrayList]$string_en_bytes = $exd_en_bytes[($data_offset_en+6+$data_chunk_size)..($data_offset_en+5+$string_size_en)]
                    $_change_to_column_separator_counter = $number_of_string_datasets - 1
                    for ($_j = 0; $_j -lt $string_en_bytes.Count; $_j++) {
                        if ( ($string_en_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                            $string_en_bytes.RemoveAt($_j)
                            foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                $string_en_bytes.Insert($_j, $_byte)
                                $_j++
                            }
                            $_j--
                            $_change_to_column_separator_counter--
                        }
                    }
                    for ($_j = $string_en_bytes.Count-1; $string_en_bytes[$_j] -eq [byte]0; $_j--) {
                        $string_en_bytes.RemoveAt($_j)
                    }
                    # There's no point to go through the script for small strings that
                    # will not have a variable, so we'll assume that the smallest possible
                    # variable is 02 10 01 03 (<br>) which is 4 bytes long.
                    if ($string_en_bytes.Count -gt 3) {
                        $result_en = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_en_bytes) )
                    } else {
                        $result_en = [System.Text.Encoding]::UTF8.GetString($string_en_bytes)
                    }

                    # Step 4. DE CSV (if EXD exists)
                    if ($CREATE_SOURCE_DE) {
                        [System.Collections.ArrayList]$string_de_bytes = $exd_de_bytes[($data_offset_de+6+$data_chunk_size)..($data_offset_de+5+$string_size_de)]
                        $_change_to_column_separator_counter = $number_of_string_datasets - 1
                        for ($_j = 0; $_j -lt $string_de_bytes.Count; $_j++) {
                            if ( ($string_de_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                                $string_de_bytes.RemoveAt($_j)
                                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                    $string_de_bytes.Insert($_j, $_byte)
                                    $_j++
                                }
                                $_j--
                                $_change_to_column_separator_counter--
                            }
                        }
                        for ($_j = $string_de_bytes.Count-1; $string_de_bytes[$_j] -eq [byte]0; $_j--) {
                            $string_de_bytes.RemoveAt($_j)
                        }
                        if ($string_de_bytes.Count -gt 3) {
                            $result_de = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_de_bytes) )
                        } else {
                            $result_de = [System.Text.Encoding]::UTF8.GetString($string_de_bytes)
                        }
                    }
                    # Step 5. FR CSV (if EXD exists)
                    if ($CREATE_SOURCE_FR) {
                        [System.Collections.ArrayList]$string_fr_bytes = $exd_fr_bytes[($data_offset_fr+6+$data_chunk_size)..($data_offset_fr+5+$string_size_fr)]
                        $_change_to_column_separator_counter = $number_of_string_datasets - 1
                        for ($_j = 0; $_j -lt $string_fr_bytes.Count; $_j++) {
                            if ( ($string_fr_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                                $string_fr_bytes.RemoveAt($_j)
                                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                    $string_fr_bytes.Insert($_j, $_byte)
                                    $_j++
                                }
                                $_j--
                                $_change_to_column_separator_counter--
                            }
                        }
                        for ($_j = $string_fr_bytes.Count-1; $string_fr_bytes[$_j] -eq [byte]0; $_j--) {
                            $string_fr_bytes.RemoveAt($_j)
                        }
                        if ($string_fr_bytes.Count -gt 3) {
                            $result_fr = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_fr_bytes) )
                        } else {
                            $result_fr = [System.Text.Encoding]::UTF8.GetString($string_fr_bytes)
                        }
                    }

                    # Step 6. JA CSV (if EXD exists)
                    if ($CREATE_SOURCE_JA) {
                        [System.Collections.ArrayList]$string_ja_bytes = $exd_ja_bytes[($data_offset_ja+6+$data_chunk_size)..($data_offset_ja+5+$string_size_ja)]
                        $_change_to_column_separator_counter = $number_of_string_datasets - 1
                        for ($_j = 0; $_j -lt $string_ja_bytes.Count; $_j++) {
                            if ( ($string_ja_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                                $string_ja_bytes.RemoveAt($_j)
                                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                    $string_ja_bytes.Insert($_j, $_byte)
                                    $_j++
                                }
                                $_j--
                                $_change_to_column_separator_counter--
                            }
                        }
                        for ($_j = $string_ja_bytes.Count-1; $string_ja_bytes[$_j] -eq [byte]0; $_j--) {
                            $string_ja_bytes.RemoveAt($_j)
                        }
                        if ($string_ja_bytes.Count -gt 3) {
                            $result_ja = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_ja_bytes) )
                        } else {
                            $result_ja = [System.Text.Encoding]::UTF8.GetString($string_ja_bytes)
                        }
                    }

                    # Step 7. RU CSV (if requested and EXD exists)
                    # - Get the translation string from target EXD
                    # - Change first <$number_of_string_datasets> 0x00 bytes to column separator
                    # - Remove the rest of 0x00 bytes from the end of the string
                    # - Change variables to more human-friendly format via my function
                    # - (Run-time choice) Add <index_hex>_ at the start of the string
                    if ($CREATE_TARGET_RU) {
                        [System.Collections.ArrayList]$string_ru_bytes = $exd_ru_bytes[($data_offset_ru+6+$data_chunk_size)..($data_offset_ru+5+$string_size_ru)]
                        $_change_to_column_separator_counter = $number_of_string_datasets - 1
                        for ($_j = 0; $_j -lt $string_ru_bytes.Count; $_j++) {
                            if ( ($string_ru_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                                $string_ru_bytes.RemoveAt($_j)
                                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                    $string_ru_bytes.Insert($_j, $_byte)
                                    $_j++
                                }
                                $_j--
                                $_change_to_column_separator_counter--
                            }
                        }
                        for ($_j = $string_ru_bytes.Count-1; $string_ru_bytes[$_j] -eq [byte]0x00; $_j--) {
                            $string_ru_bytes.RemoveAt($_j)
                        }
                        if ($string_ru_bytes.Count -gt 3) {
                            $result_ru = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_ru_bytes) )
                        } else {
                            $result_ru = [System.Text.Encoding]::UTF8.GetString($string_ru_bytes)
                        }
                        $index_hex = "{0:X}" -f [uint32]$index_result
                        if ($WRITE_INDEX_UNDERSCORE_IN_TARGET) {
                            $result_ru = "$($index_hex)_$result_ru"
                        }
                    }

                    # Step 8. RUEN CSV (if requested and EXD exists)
                    if ($CREATE_TARGET_RUEN) {
                        [System.Collections.ArrayList]$string_ruen_bytes = $exd_ruen_bytes[($data_offset_ruen+6+$data_chunk_size)..($data_offset_ruen+5+$string_size_ruen)]
                        $_change_to_column_separator_counter = $number_of_string_datasets - 1
                        for ($_j = 0; $_j -lt $string_ruen_bytes.Count; $_j++) {
                            if ( ($string_ruen_bytes[$_j] -eq [byte]0x00) -and ($_change_to_column_separator_counter -gt 0) ) {
                                $string_ruen_bytes.RemoveAt($_j)
                                foreach ($_byte in $COLUMN_SEPARATOR_BYTE) {
                                    $string_ruen_bytes.Insert($_j, $_byte)
                                    $_j++
                                }
                                $_j--
                                $_change_to_column_separator_counter--
                            }
                        }
                        for ($_j = $string_ruen_bytes.Count-1; $string_ruen_bytes[$_j] -eq [byte]0x00; $_j--) {
                            $string_ruen_bytes.RemoveAt($_j)
                        }
                        if ($string_ruen_bytes.Count -gt 3) {
                            $result_ruen = [System.Text.Encoding]::UTF8.GetString( $(Convert-VariablesToTags $string_ruen_bytes) )
                        } else {
                            $result_ruen = [System.Text.Encoding]::UTF8.GetString($string_ruen_bytes)
                        }
                        $index_hex = "{0:X}" -f [uint32]$index_result
                        if ($WRITE_INDEX_UNDERSCORE_IN_TARGET) {
                            $result_ruen = "$($index_hex)_$result_ruen"
                        }
                    }
                
                    # Step 9. Compiling results into all of the future CSV files.
                    if ($CREATE_SOURCE_EN) {
                        $null = $csv_en.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_en
                                id = ''
                                fuzzy = 'False'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                    if ($CREATE_SOURCE_DE) {
                        $null = $csv_de.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_de
                                id = ''
                                fuzzy = 'False'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                    if ($CREATE_SOURCE_FR) {
                        $null = $csv_fr.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_fr
                                id = ''
                                fuzzy = 'False'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                    if ($CREATE_SOURCE_JA) {
                        $null = $csv_ja.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_ja
                                id = ''
                                fuzzy = 'False'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                    if ($CREATE_TARGET_RU) {
                        $null = $csv_ru.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_ru
                                id = ''
                                fuzzy = 'True'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                    if ($CREATE_TARGET_RUEN) {
                        $null = $csv_ruen.Add([PSCustomObject]@{
                                location = ''
                                source = $result_en
                                target = $result_ruen
                                id = ''
                                fuzzy = 'True'
                                context = $index_result
                                translator_comments = ''
                                developer_comments = ''
                            })
                    }
                }
                Write-Progress -Activity "Converting EXD to CSV" -Completed
                $stopwatch.Stop()
                "$($base_name): Done - $($stopwatch.Elapsed.ToString())"

                if ($CREATE_SOURCE_EN -and !$csv_en) {
                    "$($base_name): Something went wrong. EN CSV turned out empty.`n"
                    continue
                }
                if ($CREATE_SOURCE_DE -and !$csv_de) {
                    "$($base_name): Something went wrong. DE CSV turned out empty.`n"
                    continue
                }
                if ($CREATE_SOURCE_FR -and !$csv_fr) {
                    "$($base_name): Something went wrong. FR CSV turned out empty.`n"
                    continue
                }
                if ($CREATE_SOURCE_JA -and !$csv_ja) {
                    "$($base_name): Something went wrong. JA CSV turned out empty.`n"
                    continue
                }
                if ($CREATE_TARGET_RU -and !$csv_ru) {
                    "$($base_name): Something went wrong. RU CSV turned out empty.`n"
                    continue
                }
                if ($CREATE_TARGET_RUEN -and !$csv_ruen) {
                    "$($base_name): Something went wrong. RUEN CSV turned out empty.`n"
                    continue
                }
                if (!$bin_en_file) {
                    "$($base_name): Something went wrong. EN binary file turned out empty.`n"
                    continue
                }
                $bin_path = "$BIN_DIR$SUB_PATH$($exd_en_files[$_page].BaseName).bin"
                Set-Content -Value $bin_en_file -Encoding Byte -Path $bin_path
                "$bin_path exported."
            }
        } else {
            "$($base_name): Nothing to create."
        }
        if ($CREATE_SOURCE_EN) {
            $csv_en | Export-Csv -Path $csv_en_path -NoTypeInformation -Encoding UTF8
            "$csv_en_path exported."
        }
        if ($CREATE_SOURCE_DE) {
            $csv_de | Export-Csv -Path $csv_de_path -NoTypeInformation -Encoding UTF8
            "$csv_de_path exported."
        }
        if ($CREATE_SOURCE_FR) {
            $csv_fr | Export-Csv -Path $csv_fr_path -NoTypeInformation -Encoding UTF8
            "$csv_fr_path exported."
        }
        if ($CREATE_SOURCE_JA) {
            $csv_ja | Export-Csv -Path $csv_ja_path -NoTypeInformation -Encoding UTF8
            "$csv_ja_path exported."
        }
        if ($CREATE_TARGET_RU) {
            $csv_ru | Export-Csv -Path $csv_ru_path -NoTypeInformation -Encoding UTF8
            "$csv_ru_path exported."
        }
        if ($CREATE_TARGET_RUEN) {
            $csv_ruen | Export-Csv -Path $csv_ruen_path -NoTypeInformation -Encoding UTF8
            "$csv_ruen_path exported."
        }
        ""
    }
    "Done.`n"
}