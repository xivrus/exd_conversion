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

$input_string = Read-Host "Paste the string`nhere"
$ByteArray = [System.Text.Encoding]::UTF8.GetBytes($input_string)
$input_string = Convert-ByteArrayToHexString $ByteArray -Delimiter '' -Width $ByteArray.Count

# We'll start with <br> real quick since they're the easiest and safest to clear
$memory_br = $(Select-String -InputObject $input_string -Pattern "3C62723E" -AllMatches).Matches # "<br>"
foreach ($match in $memory_br) {
    $input_string = $input_string.Remove($match.Index, 8).Insert($match.Index, "02100103")
}

$start_memory = [System.Collections.ArrayList]@()
$looking_for_var = $true
$error_100 = $false # TODO: Make it global in main file

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
            "WARNING! Input variable will have 0x00 byte in its size."
            "My testing showed that FFXIV doesn't show the whole string because of this."
            "Another side effect I can think of is that 0x00 is normally used in EXD file to separate"
            "values from different 'columns'."
            "Increase or decrease size of any option by 1 to work around this issue.`n"
            $error_100 = $true
            break
        }
        if ($size -gt 256) {
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
        if (($size-1 -gt 0) -and (($size - 1) % 0x100 -eq 0)) {
            "WARNING! Input variable will have 0x00 byte in its size."
            "My testing showed that FFXIV doesn't show the whole string because of this."
            "Another side effect I can think of is that 0x00 is normally used in EXD file to separate"
            "values from different 'columns'."
            "Increase or decrease size of any option by 1 to work around this issue.`n"
            $error_100 = $true
            break
        }
        $input_string = $input_string.Remove($i, 10).Insert($i, "03")
        if ($size -gt 257) {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F2{1:X4}" -f $type, ($size-1)))
            $i -= 4
        } elseif ($size -gt 215) {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F0{1:X2}" -f $type, ($size-1)))
            $i -= 6
        } else {
            $input_string = $input_string.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}{1:X2}" -f $type, $size))
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

"`n$input_string"