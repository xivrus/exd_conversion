﻿$host.UI.RawUI.WindowTitle = "CSV -> EXD (Ultimate)"

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
function Convert-TagsToVariables
{
################################################################
#.Synopsis
# Convert variable tags that were generated by "_EXDtoCSV (Extreme).ps1"
# into 0x02..0x03 variables. Output is ByteArray.
#.Parameter ByteArray
# System.Byte[] array of bytes of the target string.
#.Example
# [Byte[]] $x = @( [bytes that result in string "<var 08 E905 ((а)) (()) /var>"] )
# Convert-TagsToVariables $x
#
# @(0x02,0x08,0x09,0xE9,0x05,0xFF,0x03,0xD0,0xB0,0xFF,0x01,0x03)
################################################################
[CmdletBinding()] Param (
[Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Byte[]] $ByteArray
)
# It's much easier to operate with the string as an actual string so we're gonna convert it.
$input_string = Convert-ByteArrayToHexString $ByteArray -Delimiter '' -Width $ByteArray.Count

# We'll start with <br>, column separator, and <nl> real quick since they're the easiest and safest to clear
$memory = $(Select-String -InputObject $input_string -Pattern "3C62723E" -AllMatches).Matches # "<br>"
foreach ($match in $memory) {
    $input_string = $input_string.Remove($match.Index, 8).Insert($match.Index, "02100103")
}
$column_separator_hex = Convert-ByteArrayToHexString $COLUMN_SEPARATOR_BYTE -Delimiter ''
$memory = $(Select-String -InputObject $input_string -Pattern $column_separator_hex -AllMatches).Matches
if ($memory) { [array]::Reverse($memory) }
# String size will change so indexes will not match anymore.
# Working on the string from the end to the start mitigates this issue.
foreach ($match in $memory) {
    $input_string = $input_string.Remove($match.Index, $column_separator_hex.Length).Insert($match.Index, "00")
}
$memory = $(Select-String -InputObject $input_string -Pattern "3C6E6C3E" -AllMatches).Matches # "<nl>"
if ($memory) { [array]::Reverse($memory) } # See explanation above
foreach ($match in $memory) {
    $input_string = $input_string.Remove($match.Index, 8).Insert($match.Index, "0A")
}

$start_memory = [System.Collections.ArrayList]@()
$looking_for_var = $true

for ($i = 0; $i -lt $input_string.Length-8; $i += 2) {
    if ( $looking_for_var -and ($input_string.Substring($i, 10) -eq '3C76617220') ) { # '<var '
        $looking_for_var = $false
        $null = $start_memory.Add($i) # Remember position for later. String manipulation will happen at the ends of vars and options
        $i += 14 # Skipping over the type too
    }
    if ($input_string.Substring($i, 4) -eq '2828') { # "(("
        $looking_for_var = $true
        $null = $start_memory.Add($i) # Same as above
        $i += 2
        continue
    }
    if ($input_string.Substring($i, 4) -eq '2929') { # "))"
        if ($input_string.Substring($i, 6) -eq '292929') { continue } # ")))"
        $looking_for_var = $false
        $input_string = $input_string.Remove($i, 4)
        $size = ($i - $start_memory[-1] - 4) / 2   # 4 is length of "(("
        if (($size -gt 0) -and ($size % 0x100 -eq 0)) {
            $input_string = $input_string.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF1{0:X2}" -f ($size / 0x100))
            $i += 2
        } elseif ($size -gt 256) {
            $input_string = $input_string.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF2{0:X4}" -f $size)
            $i += 4
        } elseif ($size -gt 214) {
            $input_string = $input_string.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF0{0:X2}" -f $size)
            $i += 2
        } else {
            $input_string = $input_string.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FF{0:X2}" -f ($size+1))
        }
        $start_memory.RemoveAt($start_memory.Count-1)
    }
    if ($input_string.Substring($i, 10) -eq '2F7661723E') { # "/var>"
        $looking_for_var = $true
        $type_hex = $input_string.Substring($start_memory[-1]+10, 4)
        $type = "{0}{1}" -f [char][uint32]$('0x' + $type_hex.Substring(0, 2)), [char][uint32]$('0x' + $type_hex.Substring(2, 2))
        $size = ($i - $start_memory[-1] - 14) / 2 + 1   # 14 is length of "<var XX"; +1 is 03 in the end
        $input_string = $input_string.Remove($i, 10).Insert($i, "03")
        if (($size-1 -gt 0) -and (($size - 1) % 0x100 -eq 0)) {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F1{1:X2}" -f $type, (($size-1) / 0x100) ))
            $i -= 6 
        } elseif ($size -gt 257) {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F2{1:X4}" -f $type, ($size-1) ))
            $i -= 4
        } elseif ($size -gt 215) {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F0{1:X2}" -f $type, ($size-1) ))
            $i -= 6
        } else {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}{1:X2}" -f $type, $size) )
            $i -= 8
        }
        $start_memory.RemoveAt($start_memory.Count-1)
    }
    if (-not $looking_for_var) { # " "
        if ($input_string.Substring($i, 2) -eq "20") {
            $input_string = $input_string.Remove($i, 2)
            $i -= 2
        } else {
            $byte_hex = $input_string.Substring($i, 4)
            $byte = "{0}{1}" -f [char][uint32]$('0x' + $byte_hex.Substring(0, 2)), [char][uint32]$('0x' + $byte_hex.Substring(2, 2))
            $input_string = $input_string.Remove($i, 4).Insert($i, $byte)
        }
    }
}

$ByteArray = Convert-HexStringToByteArray $input_string
return $ByteArray
}


if (!$(Test-Path '.\current') ) {
    "$PWD is not a project translation folder. (.\current folder wasn't found)"
    "Start with EXDtoCSV script in this folder to convert some files first"
    "and to generate project structure."
    Pause
    break   
}

while ($true) {
    $SILENTLY_OVERWRITE = $false
    $GLOBAL_CUSTOMIZE = $false
    $WRITE_FILE_INDEX_IN_TRANSLATION = $false
    $current_dir = "$PWD\current"
    "Current project folder is $current_dir"
    "Put EXH files into .\current\exh"
    "and CSV files into .\current\csv"
    "EXD files will be put in .\current\exd_mod, source EXDs are expected to be in .\current\exd_source"
    "Drag and drop EXH, EXD, or CSV file and press Enter,"
    "or enter 'exh' to get all EXH files in current folder and subfolders,"
    "or enter 'csv' to get all CSV files in current folder and subfolders."
    $input_answer = Read-Host ' '
    if ( $input_answer -in ('exh','csv') ) {
        switch ($input_answer.ToLower()) {
            'exh' {
                $input_answer = Get-ChildItem ".\current\exh\*.exh" -Recurse
                "$($input_answer.Count) EXHs found."
                break
                }
            'csv' {
            	$input_answer = Get-ChildItem ".\current\csv\*.csv" -Recurse
            	"$($input_answer.Count) CSVs found."
                break
            }
        }
        $_answer = $(Read-Host "Do you want to overwrite all EXD files that already exist? (Y/n)").ToLower()
        switch ($_answer) {
            "n" { break }
            default { $SILENTLY_OVERWRITE = $true; break }
        }
        "Do you want to make choices for all files right now?"
        $_answer = $(Read-Host "If not then you'll have to choose manually for each file. (Y/n)").ToLower()
        switch ($_answer) {
            "n" { break }
            default {
                $GLOBAL_CUSTOMIZE = $true
                "Choose what to do with '<index>_' at the start of translation fields:"
                $_answer = $(Read-Host "Add if doesn't exist / Remove if exists / do Nothing (a/r/N)").ToLower()
                switch ($_answer) {
                    "a" { $INDEXES_CHOICE = 1; break }
                    "r" { $INDEXES_CHOICE = 2; break }
                    default { $INDEXES_CHOICE = 0; break }
                }
                "For advanced debugging this script can also add file indexes on top of string indexes."
                "The files are going to be numbered in hex, and then the file number can go before the string index."
                "E.g. the 100th string from 12th file would have 'C_64_' at the start."
                $_answer = $(Read-Host "Add a file index at the start of all translation fields? (y/N)")
                switch ($_answer) {
                    "y" { $WRITE_FILE_INDEX_IN_TRANSLATION = $true; break }
                    default { break }
                }
                break
            }
        }

        "Keep in mind that if there are several CSVs for one EXH"
        "you'll be asked to choose one."
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

    $file_index = 0
    foreach ($input_file in $input_answer) {
        $file_index++
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
        $EXH_DIR          = "$current_dir\exh"
        $SUB_PATH         = $input_file.FullName -replace '.*?\\bin|.*?\\csv|.*?\\exd_mod|.*?\\exd_source|.*?\\exh','' -replace "$($base_name).*",''

	    # If EXH file is in 'exd_source' folder, move it to 'exh' folder and tell about it to user
        if (Test-Path "$EXD_SOURCE_DIR$SUB_PATH$($base_name).exh") {
            if (!$(Test-Path "$EXH_DIR$SUB_PATH")) { $null = New-Item "$EXH_DIR$SUB_PATH" -ItemType Directory }
            Move-Item "$EXD_SOURCE_DIR$SUB_PATH$($base_name).exh" "$EXH_DIR$SUB_PATH$($base_name).exh" -Force
            "$($base_name): EXH file was found in 'exd_source' - moved to 'exh' folder."
        }
	    # Collect data from EXH
        $exh_path = "$EXH_DIR$SUB_PATH$($base_name).exh"
        if (!$(Test-Path -Path $exh_path)) {
            "$($base_name): EXH file at $exh_path wasn't found. Skipping.`n"
            continue
        } else { "$($base_name): EXH file found at $exh_path." }
        while ($true) {
            $exh_bytes = [System.IO.File]::ReadAllBytes($exh_path)
            if ($exh_bytes) { break }
            "$($base_name): Error while trying to read EXH file at"
            $exh_path
            "The file is probably locked by some program."
            $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
            if ($_answer -eq 'skip') { "$($base_name): Skipping.`n"; continue }
        }
        $data_chunk_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x6..0x7] -Delimiter '' -Prepend '0x')
        $number_of_datasets = [uint32](Convert-ByteArrayToHexString $exh_bytes[0x8..0x9] -Delimiter '' -Prepend '0x')
        $number_of_pages = [uint32](Convert-ByteArrayToHexString $exh_bytes[0xA..0xB] -Delimiter '' -Prepend '0x')
        $string_offsets_in_datachunks = New-Object System.Collections.ArrayList
        for ($_i = 0; $_i -lt $number_of_datasets; $_i++) {
            $_offset = 0x20 + $_i*4
            if ( @(Compare-Object $exh_bytes[$_offset..($_offset+1)] @( 0x00, 0x00 ) ).Length -eq 0 ) {
                $_string_offset = [uint32](Convert-ByteArrayToHexString $exh_bytes[($_offset+2)..($_offset+3)] -Delimiter '' -Prepend '0x')
                $null = $string_offsets_in_datachunks.Add($_string_offset)
            }
        }
        $page_table = New-Object System.Collections.ArrayList
        for ($_i = 0; $_i -lt $number_of_pages; $_i++) {
            $_offset = 0x20 + $number_of_datasets * 4 + $_i * 8
            $_page_entry = [uint32](Convert-ByteArrayToHexString $exh_bytes[$_offset..($_offset+3)] -Delimiter '' -Prepend '0x')
            $_page_size = [uint32](Convert-ByteArrayToHexString $exh_bytes[($_offset+4)..($_offset+7)] -Delimiter '' -Prepend '0x')
            $null = $page_table.Add( @{ PageEntry = $_page_entry; PageSize = $_page_size } )
        }

        # Read (or choose and read) CSV file
        $csv_files = Get-ChildItem -Path "$CSV_DIR$SUB_PATH$($base_name)*.csv" -Name
        if ($null -eq $csv_files) {
            "$($base_name): .csv file that has '$base_name' in its name wasn't found. Skipping.`n"
            continue
        }
        if ($csv_files.Count -gt 1) {
            "$($base_name): Several CSV files were found:"
            for ($_i = 0; $_i -lt $csv_files.Count; $_i++) {
                "  $($_i+1). $($csv_files[$_i])"
            }
            "  0. Skip"
            $skip = $false
            while ($true) {
                $_choice = [int]$(Read-Host "Choose one")
                if ($_choice -eq 0) { $skip = $true; break }
                $_choice--
                if ( ($_choice -gt -1) -and ($_choice -lt $csv_files.Count) ) {
                    "$($csv_files[$_choice]) was chosen."
                    $csv_path = "$CSV_DIR$SUB_PATH$($csv_files[$_choice])"
                    break
                }
                "Try again."
            }
            if ($skip) { "$($base_name): Skipped"; continue }
        } else {
            "$($base_name): $csv_files was found."
            $csv_path = "$CSV_DIR$SUB_PATH$csv_files"
        }
        # Read the CSV
        while ($true) {
            $csv = Import-Csv $csv_path -Encoding UTF8
            if ($csv) { break }
            "$($base_name): Error while trying to read CSV file at"
            $csv_path
            "The file is probably locked by some program."
            $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
            if ($_answer -eq 'skip') { continue }
        }
        # Ask questions
        if (!$GLOBAL_CUSTOMIZE) {
            "$($base_name): Choose what to do with '<index>_' at the start of translation fields:"
            $_answer = $(Read-Host "Add if doesn't exist / Remove if exists / do Nothing (a/r/N)").ToLower()
            switch ($_answer) {
                "a" { $INDEXES_CHOICE = 1; break }
                "r" { $INDEXES_CHOICE = 2; break }
                default { $INDEXES_CHOICE = 0; break }
            }
        }
        if (!$SILENTLY_OVERWRITE -and ($page_table.Count -gt 1)) {
            $_answer = $(Read-Host "$($base_name): Several EXDs will be generated from this CSV. Overwrite them? (Y/n)").ToLower()
            switch ($_answer) {
                "n" { $silently_overwrite_multipage = $false; continue }
                default {
                    $silently_overwrite_multipage = $true
                    "Note: If any of generated EXDs is the same as the one that already exists"
                    "      it will not be overwritten anyway."
                    break
                }
            }
        }

        # Conversion start
        $current_row = 0
        $current_progress = 0
        foreach ($page in $page_table) {
            $exd_file_name = "$($base_name)_$($page.PageEntry)_en"
            $bin_path = "$BIN_DIR$SUB_PATH$exd_file_name.bin"
            if (!(Test-Path $bin_path)) {
                "$($base_name): BIN file wasn't found at $bin_path."
                "$($base_name): Skipping.`n"
                break
            }
            $exd_path = "$EXD_DIR$SUB_PATH$exd_file_name.exd"
            $exd_exists = Test-Path $exd_path
            if (!$SILENTLY_OVERWRITE -and !$silently_overwrite_multipage -and $exd_exists) {
                $_answer = $(Read-Host "$($base_name): $exd_path already exists. Overwrite? (Y/n)").ToLower()
                switch ($_answer) {
                    "n" { continue }
                    default { break }
                }
            }
            
            while ($true) {
                $bin_bytes = [System.IO.File]::ReadAllBytes($bin_path)
                if ($bin_bytes) { break }
                "$($base_name): Error while trying to read BIN file at"
                $bin_path
                "The file is probably locked by some program."
                $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                if ($_answer -eq 'skip') { continue }
            }

            # Step 1. Collect raw indexes, strings, and their offsets into the $row_data table
            #  If there are several strings per row, they are separated by 0x00 byte in
            #  source string. We'll be looking for this byte here to separate the strings
            #  in a row and get their new offsets for an according row chunk.
            $row_data = New-Object System.Collections.ArrayList
            $COLUMN_SEPARATOR = '<tab>' # Tab
            $COLUMN_SEPARATOR_BYTE = [System.Text.Encoding]::ASCII.GetBytes($COLUMN_SEPARATOR)

            # This 'if' is a workaround against single-paged files like 'addon' and 'error' that
            # don't start from $page_table[0].PageStart or skip indexes
            if ($page_table.Count -eq 1) {
                $_end = $csv.Count
            } else {
                $_end = $current_row + $page.PageSize
            }
            if ($WRITE_FILE_INDEX_IN_TRANSLATION) {
                $file_index_hex = "{0:X}_" -f $file_index
            } else {
                $file_index_hex = ""
            }

            $1_percent = $csv.Count / 100
            for ($_row = $current_row; $_row -lt $_end; $_row++) {
                if ( $_row -gt ($1_percent * $current_progress) ) {
                    Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Working on '$base_name'" -Status "$current_progress% Complete:" -PercentComplete $current_progress
                    $current_progress += 1
                }

                if ($csv[$_row].Translation -eq '') {
                    $csv[$_row].Translation = $csv[$_row].Source
                }
                if ($INDEXES_CHOICE) {
                    $exd_index_hex = "{0:X}_" -f [uint32]$csv[$_row].Index
                    switch ($INDEXES_CHOICE) {
                        1 { # Add index if doesn't exist
                            if ( $csv[$_row].Translation.StartsWith($exd_index_hex) ) { $exd_index_hex = "" }
                            break
                        }
                        2 { # Remove index if exists
                            if ( $csv[$_row].Translation.StartsWith($exd_index_hex) ) {
                                $csv[$_row].Translation = $csv[$_row].Translation.Substring($exd_index_hex.Length)
                            }
                            $exd_index_hex = ""
                            break
                        }
                    }
                } else { $exd_index_hex = "" }

                # Even though in theory we could avoid using byte arrays and pass a string instead,
                # we're still going to get byte array to be safe of PowerShell conversions.
                try {
                    if ([System.Text.Encoding]::UTF8.GetByteCount( $csv[$_row].Translation ) -gt 0) {
                        $translation_string = $file_index_hex + $exd_index_hex + $csv[$_row].Translation

                        $result_bytes = Convert-TagsToVariables $([System.Text.Encoding]::UTF8.GetBytes($translation_string))
                    } elseif ([System.Text.Encoding]::UTF8.GetByteCount( $csv[$_row].Source ) -gt 0) {
                        $source_string = $file_index_hex + $exd_index_hex + $csv[$_row].Source

                        $result_bytes = Convert-TagsToVariables $([System.Text.Encoding]::UTF8.GetBytes($source_string))
                    } else {
                        $result_string = $file_index_hex + $exd_index_hex

                        $result_bytes = [System.Text.Encoding]::ASCII.GetBytes($result_string)
                    }
                }
                catch {
                    Write-Host "$($base_name): " -NoNewline
                    Write-Host "Error at $($csv[$_row].context)." -ForegroundColor Red
                    $error_var = $true
                }

                if (!$error_var) {
                    # Determining offsets to columns
                    $strings_offsets = New-Object System.Collections.ArrayList
                    $null = $strings_offsets.Add( 0 )    # First string always starts at offset 0
                    for ($_index = 0; $_index -lt $result_bytes.Count; $_index++) {
                        if ($result_bytes[$_index] -eq [byte]0x00) {
                            $null = $strings_offsets.Add($_index + 1)
                        }
                    }

                    $null = $row_data.Add(@{
                        Index = [uint32]$csv[$_row].Index
                        Bytes = $result_bytes
                        OffsetsTable = $strings_offsets
                    })
                }
            }
            if ($error_var) {
                "$($base_name): It's recommended to check tags in this/these line(s). Skipping.`n"
                $error_var = $false
                break
            }

            # Step 2. Edit BIN data
            #$current_progress = 0
            #$1_percent = $row_data.Count / 100
            for ($_i = 0; $_i -lt $row_data.Count; $_i++) {
                #if ( $i -gt ($1_percent * $current_progress) ) {
                #    Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Step 2. Editing BIN data" -Status "$current_progress% Complete:" -PercentComplete $current_progress
                #    $current_progress += 1
                #}
                $_offset = $_i * $data_chunk_size
                $_string_offsets_bytes = New-Object System.Collections.ArrayList
                foreach ($_raw_data_piece in $row_data[$_i].OffsetsTable) {
                    $_string_offset_array = New-Object System.Collections.ArrayList
                    foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_raw_data_piece)) ) {
                        $null = $_string_offset_array.Add( $_byte )
                    }
                    $null = $_string_offsets_bytes.Add($_string_offset_array)
                }
                $_count = 0
                for ($_j = 0; $_j -lt $data_chunk_size; $_j++) {
                    if ($string_offsets_in_datachunks -contains $_j) {
                        for ($_k = 0; $_k -lt 4; $_k++) {
                            if ($null -eq $_string_offsets_bytes[$_count]) {
                                $bin_bytes[($_offset+$_j+$_k)] = [byte]0x00
                            } else {
                                $bin_bytes[($_offset+$_j+$_k)] = $_string_offsets_bytes[$_count][$_k]
                            }
                        }
                        $_count++
                    }
                }
            }
            #Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Step 2. Editing BIN data" -Status "Completed" -Completed

            # Step 3. Setting up actual data table that's going to go in file
            #         + Remembering offsets for the offset table
            $offset_table_size = $row_data.Count * 8
            $data_table_offset = $offset_table_size + 0x20

            $index_offset_table = New-Object System.Collections.ArrayList
            $data_table = New-Object System.Collections.ArrayList
            $_current_offset = $data_table_offset
            #$current_progress = 0
            #$1_percent = $row_data.Count / 100
            # $_i = 1 # For debug to jump to specified string in CSV
            for ($_i = 0; $_i -lt $row_data.Count; $_i++) {
                #if ( $i -gt ($1_percent * $current_progress) ) {
                #    Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Step 3. Preparing data table" -Status "$current_progress% Complete:" -PercentComplete $current_progress
                #    $current_progress += 1
                #}
                $null = $index_offset_table.Add(@{
                    Index = $row_data[$_i].Index
                    Offset = $_current_offset
                })
                $_size = $data_chunk_size + $row_data[$_i].Bytes.Length
                $_zeros = 4 - (2 + $_size) % 4     # Seems like padding is always aligned to 4
                foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f ($_size + $_zeros)) ) ) {
                    $null = $data_table.Add( $_byte )
                }
                $null = $data_table.Add( [byte]0x00 )
                $null = $data_table.Add( [byte]0x01 )
                for ($_j = 0; $_j -lt $data_chunk_size; $_j++) {
                    $null = $data_table.Add( $bin_bytes[(($_i)*$data_chunk_size + $_j)] )
                }
                if ($row_data[$_i].Bytes.Count -gt 0) {
                    foreach ($_byte in $row_data[$_i].Bytes ) {
                        $null = $data_table.Add( $_byte )
                    }
                }
                for ($_j = 0; $_j -lt $_zeros; $_j++) {
                    $null = $data_table.Add( [byte]0x00 )
                }
                $_current_offset += 6 + $_size + $_zeros
            }
            [byte[]]$data_table = $data_table.ToArray() # Checking that we've got only bytes
            #Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Step 3. Preparing data table" -Status "Completed" -Completed

            # Step 4. Create offset table
            $offset_table = [System.Collections.ArrayList]@()
            foreach ($_index_offset_piece in $index_offset_table)
            {
                foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_index_offset_piece.Index) ) )
                {
                    $null = $offset_table.Add( $_byte )
                }
                foreach ($_byte in $(Convert-HexStringToByteArray ("{0:X8}" -f $_index_offset_piece.Offset) ) )
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
            if ($null -eq $exd_header) {
                "$($base_name): Something went wrong. EXD header turned out empty.`n"
                Remove-Variable data_table
                continue
            }
            if ($null -eq $offset_table) {
                "$($base_name): Something went wrong. Offset table turned out empty.`n"
                Remove-Variable data_table
                continue
            }
            if ($null -eq $data_table) {
                "$($base_name): Something went wrong. Data table turned out empty.`n"
                Remove-Variable data_table
                continue
            }
            $stream = [IO.MemoryStream]::new($exd_header + $offset_table + $data_table)
            if ($exd_exists -and $SILENTLY_OVERWRITE -and ($page_table.Count -gt 1) ) {
                $_hash1 = Get-FileHash -InputStream $stream
                $_hash2 = Get-FileHash -Path $exd_path
                if ($_hash1.Hash -ne $_hash2.Hash) {
                    Set-Content -Value ($exd_header + $offset_table + $data_table) -Encoding Byte -Path $exd_path
                    "$($base_name): $exd_path exported."
                } else { "$($base_name): $exd_path is identical, skipped." }
            } else {
                Set-Content -Value ($exd_header + $offset_table + $data_table) -Encoding Byte -Path $exd_path
                "$($base_name): $exd_path exported."
            }
            Remove-Variable data_table
            $current_row += $page.PageSize
        }
        $silently_overwrite_multipage = $false
        # I have no idea why progress bar doesn't work after calling and completing it once so I'll just unite it then
        Write-Progress -Activity "Converting CSV to EXD" -CurrentOperation "Working on '$base_name'" -Status "Completed" -Completed
    }

    if ($WRITE_FILE_INDEX_IN_TRANSLATION) {
        "Conversion complete. File indexes:"
        for ($_i = 0; $_i -lt $input_answer.Count; $_i++){
            "{0:X} - {1}" -f ($_i+1), ($input_answer[$_i].BaseName)
        }
        "`n"
    } else {
        "Conversion complete.`n"
    }
}