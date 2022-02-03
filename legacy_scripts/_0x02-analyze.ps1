$host.UI.RawUI.WindowTitle = "0x02-analyze.ps1"
Clear-Host

while ($true) {
$input_string = Read-Host "Paste the string`nhere"
if ($input_string.Length -eq 0) {
    "No string, bye."
    pause
    continue
}
if ($input_string.Length % 2 -eq 1) {
    "The input length is of uneven size - $($input_string.Length). Copy and paste more carefully."
    pause
    continue
}

$lines = @($null) * ($input_string.Length / 2)
$depth_memory = [System.Collections.ArrayList]@()
$max_depth = 0
$looking_for_02 = $true

for ($i = 0; $i -lt $input_string.Length; $i += 2) {
    while ($i -eq $depth_memory[-1]) {
        $depth_memory.RemoveAt($depth_memory.Count-1)
        $looking_for_02 = $true
    }
    $lines[($i/2)] = @($null)
    #if ( ($i+8 -lt $input_string.Length) -and ($input_string.Substring($i, 8) -ne '02020203') ) { $i += 6 } # 02020203 doesn't abide normal rules and messes things up so we'll skip to 03
    if ( ($input_string.Substring($i, 2) -eq '02') -and $looking_for_02 ) { 
        $looking_for_02 = $false
        $byte_after_FF = $input_string.Substring( ($i+4), 2)
        
        $size = 0
        switch ($byte_after_FF) {
            "F2" {
                $size = [uint32]('0x' + $input_string.Substring( ($i+6), 4)) + 1
                $null = $depth_memory.Add( $i+($size+5)*2 )
                break }
            "F1" {
                $size = [uint32]('0x' + $input_string.Substring( ($i+6), 2) + '00') + 1
                $null = $depth_memory.Add( $i+($size+4)*2 )
                break }
            "F0" {
                $size = [uint32]('0x' + $input_string.Substring( ($i+6), 2)) + 1
                $null = $depth_memory.Add( $i+($size+4)*2 )
                break }
            default {
                $size = [uint32]('0x' + $byte_after_FF)
                $null = $depth_memory.Add( $i+($size+3)*2 )
            }
        }
        if ($depth_memory.Count -gt $max_depth) { $max_depth = $depth_memory.Count }

        $line = ''                                  # Filling for the first bytes
        switch ($byte_after_FF) {
            "F2" { $line = '──────────'; break }    # 5
            "F1" { $line = '────────'; break }      # 4
            "F0" { $line = '────────'; break }      # 4
            default { $line = '──────' }            # 3
        }
        for ($j = 0; $j -lt $size-1; $j++) { $line += '──' } # And then the rest. Size is guaranteed to be 1+
        $lines[($i/2)] = @($null) * $depth_memory.Count
        $lines[($i/2)][$depth_memory.Count-1] = ('└' + $line + '┘')

        switch ($byte_after_FF) {
            "F2" { $i += 10; break }
            "F1" { $i += 8; break }
            "F0" { $i += 8; break }
            default { $i += 6 }
        }
    }
    if ($input_string.Substring($i, 2) -eq 'FF') {
        $looking_for_02 = $true
        $byte_after_FF = $input_string.Substring( ($i+2), 2)

        $size = 0
        switch ($byte_after_FF) {
            "F2" { $size = [uint32]('0x' + $input_string.Substring( ($i+4), 4)) + 1; break }
            "F1" { $size = [uint32]('0x' + $input_string.Substring( ($i+4), 2) + '00') + 1; break }
            "F0" { $size = [uint32]('0x' + $input_string.Substring( ($i+4), 2)) + 1; break }
            default { $size = [uint32]('0x' + $byte_after_FF) }
        }
        $depth_memory.Add( $i+$size*2 ) > $null
        if ($depth_memory.Count -gt $max_depth) { $max_depth = $depth_memory.Count }

        $line = ''
        switch ($byte_after_FF) {
            "F2" { $line = '╌╌╌╌'; break }
            "F1" { $line = '╌╌'; break }
            "F0" { $line = '╌╌'; break }
            default {}
        }
        for ($j = 0; $j -lt $size; $j++) { $line += '╌╌' }
        $lines[($i/2)] = @($null) * $depth_memory.Count
        $lines[($i/2)][$depth_memory.Count-1] = (' ╰' + $line + '╯') # We will use the first space to determine whether it's a var or an option

        switch ($byte_after_FF) {
            "F2" { $i += 6; break }
            "F1" { $i += 4; break }
            "F0" { $i += 4; break }
            default { $i += 2 }
        }
    }
    while ($i -eq $depth_memory[-1]) {
        $depth_memory.RemoveAt($depth_memory.Count-1)
        $looking_for_02 = $true
    }
}

# Pre-draw lines into array
$result_lines = @( ' ' * $input_string.Length ) * $max_depth
for ($i = $max_depth-1; $i -gt -1; $i--) {
    for ($j = 0; $j -lt $lines.Count; $j++) {
        if ($null -ne $lines[$j]) {
            if ($null -ne $lines[$j][$i]) {
                if ($lines[$j][$i][0] -eq ' ') {                   # If this is an option..
                    $position = $j*2 + 1
                    $line_length = $lines[$j][$i].Length-1
                    $lines[$j][$i] = $lines[$j][$i].Substring(1)
                } else {                                           # ...Otherwise it's a var
                    $position = $j*2
                    $line_length = $lines[$j][$i].Length
                }
                $result_lines[$i] = $result_lines[$i].Remove($position, $line_length).Insert($position, $lines[$j][$i])
            }
        }
    }
}
[array]::Reverse($result_lines)

"
Results:"
# Showing actual symbols above the string to see normal text
$ASCII_PRINTABLE_CHARS = @( 0x20..0x7E )
$UTF8_FIRST_BYTES_RUS = @( 0xD0..0xD1 )
for ($_i = 0; $_i -lt $input_string.Length; $_i += 2) {
    $_symbol = [byte]('0x' + $input_string.Substring($_i, 2))
    if ( $ASCII_PRINTABLE_CHARS -contains $_symbol ) {
        Write-Host "$([char]$_symbol) " -NoNewline
        continue
    }
    if ( $UTF8_FIRST_BYTES_RUS -contains $_symbol ) {
        $_i += 2
        $_second_symbol = [byte]('0x' + $input_string.Substring($_i, 2))
        $_utf8char_bytes = @( $_symbol, $_second_symbol )
        $_utf8char = [System.Text.Encoding]::UTF8.GetString($_utf8char_bytes)
        Write-Host "$_utf8char   " -NoNewline
        continue
    }
    Write-Host '  ' -NoNewline
}
$ofs = "`n"   # Setting the array separator to a new line symbol for $result_lines
"
$input_string
$result_lines

"
}