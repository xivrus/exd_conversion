$host.UI.RawUI.WindowTitle = "0x02-correct.ps1"
Clear-Host

function EvenIndexOf {
    [CmdletBinding()] Param (
        [Parameter(Mandatory = $True)] [String] $String,
        [Parameter(Mandatory = $True)] [String] $Substring,
        [Parameter()] [Int] $Index = 0
    )
    
    $result = $Index
    do {
        $result = $String.IndexOf($Substring, $Index)
        $Index++
    } while ( ($result % 2 -eq 1) -and ($result -ne -1) )
    return $result
}


while ($true) {
$input_string = Read-Host "Paste 0x02..0x03 part that needs correction as a HEX string w/o spaces`nhere"
if ($input_string.Length -eq 0) {
    "No string`n"
    continue
}
if ($input_string.Length % 2 -eq 1) {
    "The input length is of uneven size - $($input_string.Length). Copy and paste more carefully.`n"
    continue
}
if ($input_string.Substring(0,2) -ne "02") {
    "The input does not start with 0x02. Make sure you copy the whole thing.`n"
    continue
}
if ($input_string.Substring($input_string.Length-2) -ne "03") {
    "The input does not end with 0x03. Make sure you copy the whole thing.`n"
    continue
}
$continue_flag = $false

$options_index_size_table = [System.Collections.ArrayList]@()    # In this table each row will have index of an option and the option size
$skipped_vars_table = [System.Collections.ArrayList]@()  # This table will keep indexes of skipped variables for user reference
$current_position = EvenIndexOf -String $input_string -Substring 'FF'
do {
    $option_size_index = $current_position + 2      # Where to write new size
    $byte_after_FF = $input_string.Substring( $option_size_index, 2)
    $option_start = $option_size_index + 2          # Where payload begins
    switch ($byte_after_FF) {
        "F0" { $option_start += 2; break }
        "F2" { $option_start += 4 }
    }
    $current_position = $option_start

    # The following loop skips all other variables inside an option,
    # while also noting skipped variables in $skipped_vars_table (only first layer).
    # The result is $current_position after all these variables
    do {
        $next_FF_position = EvenIndexOf -String $input_string -Substring 'FF' -Index $current_position
        $next_02_position = EvenIndexOf -String $input_string -Substring '02' -Index $current_position
        if ( ($next_02_position -lt $next_FF_position) -and ($next_02_position -ne -1)) {
            $next_02_size_first_byte = $input_string.Substring( ($next_02_position + 4), 2)
            switch ($next_02_size_first_byte) {
                "F0" {
                    $next_02_size = [uint32]("0x" + $input_string.Substring( ($next_02_position + 6), 2)) + 1
                    $next_02_first_bytes_quantity = 4
                    break
                }
                "F2" {
                    $next_02_size = [uint32]("0x" + $input_string.Substring( ($next_02_position + 6), 4)) + 1
                    $next_02_first_bytes_quantity = 5
                    break
                }
                default {
                    $next_02_size = [uint32]("0x" + $next_02_size_first_byte)
                    $next_02_first_bytes_quantity = 3
                }
            }
            $current_position = $next_02_position + $next_02_first_bytes_quantity * 2 + $next_02_size * 2
            $null = $skipped_vars_table.Add($next_02_position / 2)
        }
    } while ( ($next_02_position -lt $next_FF_position) -and ($next_02_position -ne -1) )
    
    $option_end = $(EvenIndexOf -String $input_string -Substring 'FF' -Index $current_position) + 2    # Where payload ends
    if ($option_end -eq 1) { $option_end = $input_string.Length }    # The last option ends at the end of the whole string
    
    $option_size = ($option_end - $option_start) / 2
    if ( ($option_size-1 -gt 0) -and (($option_size-1) % 0x100 -eq 0) ) {
        "WARNING! Variable option that starts from index $option_start will have 0x00 byte in its size."
        "My testing showed that FFXIV doesn't show the whole string because of this."
        "Another side effect I can think of is that 0x00 is normally used in EXD file to separate"
        "values from different 'columns'."
        "Increase or decrease variable size by 1 to work around this issue.`n"
        $continue_flag = $true
        break
    }
    if ($option_size -gt 256) {
        $null = $options_index_size_table.Add( @($option_size_index, $('F2{0:X4}' -f ($option_size-1) )) )
    } else {
        if ($option_size -gt 215) {
            $null = $options_index_size_table.Add( @($option_size_index, $('F0{0:X2}' -f ($option_size-1) )) )
        } else {
            $null = $options_index_size_table.Add( @($option_size_index, $('{0:X2}' -f $option_size)) )
        }
    }

    $current_position = $option_end - 2
} while ($option_end -ne $input_string.Length)
if ($continue_flag) { continue }

# Writing new values

# Whenever we write a new size with F0/F2, total size of the string will change and all offests will move.
# $offset will remember all these movements and adjust the indexes.
$offset = 0
$result_string = $input_string
foreach ($i in $options_index_size_table) {
    $size_first_byte = $input_string.Substring($i[0], 2)
    switch ($size_first_byte) {
        "F0"    { $result_string = $result_string.Remove($i[0]+$offset, 4).Insert($i[0]+$offset, $i[1]); $offset += 2; break }
        "F2"    { $result_string = $result_string.Remove($i[0]+$offset, 6).Insert($i[0]+$offset, $i[1]); $offset += 4; break }
        default { $result_string = $result_string.Remove($i[0]+$offset, 2).Insert($i[0]+$offset, $i[1]) }
    }
}
$input_string_size_first_byte = $input_string.Substring(4, 2)
switch ($input_string_size_first_byte) {
    "F0"    { $result_string = $result_string.Remove(4,4); break }
    "F2"    { $result_string = $result_string.Remove(4,6); break }
    default { $result_string = $result_string.Remove(4,2) }
}
$total_size = $result_string.Substring(4).Length / 2
if ( ($total_size-1 -gt 0) -and (($total_size-1) % 0x100 -eq 0) ) {
    "WARNING! Input variable will have 0x00 byte in its size."
    "My testing showed that FFXIV doesn't show the whole string because of this."
    "Another side effect I can think of is that 0x00 is normally used in EXD file to separate"
    "values from different 'columns'."
    "Increase or decrease size of any option by 1 to work around this issue.`n"
    continue
}
if ($total_size -gt 256) {
    $result_string = $result_string.Insert(4, $('F2{0:X4}' -f ($total_size-1)) )
} else {
    if ($total_size -gt 215) {
        $result_string = $result_string.Insert(4, $('F0{0:X2}' -f ($total_size-1)) )
    } else {
        $result_string = $result_string.Insert(4, $('{0:X2}' -f $total_size) )
    }
}

$ofs = ', '   # Setting array separator for $skipped_vars_table
"Result:
$result_string
Indexes of skipped variables (none if empty):
$skipped_vars_table

"
}