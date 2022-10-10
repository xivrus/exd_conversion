# Function's source: https://www.sans.org/blog/powershell-byte-array-and-hex-functions/
# Edited for my scripts
function Convert-ByteArrayToHexString
{
################################################################
#.Synopsis
# Returns a hex representation of a System.Byte[] array as
# one or more strings. Hex format is as follows:
# 0x41424344
#.Parameter ByteArray
# System.Byte[] array of bytes to put into the file. If you
# pipe this array in, you must pipe the [Ref] to the array.
# Also accepts a single Byte object instead of Byte[].
#.Example
# [Byte[]] $x = 0x41,0x42,0x43,0x44
# Convert-ByteArrayToHexString $x
#
# 0x41424344
################################################################
[CmdletBinding()] Param (
    [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Byte[]] $ByteArray
)

if ($ByteArray.Length -eq 0) { Return }
Return '0x' + [System.BitConverter]::ToString($ByteArray) -replace '-',''
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

# The following functions were written by me
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
    [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [System.Collections.Generic.List[byte]] $ByteArray
    )
    
    $depth_memory = [System.Collections.Generic.List[int]]::new()
    $looking_for_02 = $true
    
    # Array size will change, so this will keep track of how much
    # and adjust values accordingly
    $offset = 0
    
    # Workaround variable to skip FFs.
    # Case 1: - Solved!
    # There are several strings in addon_0_xx.exd with FE FF and
    # FE FF FF FF FF structures. It seems like FE makes the game to
    # ignore FFs for, I assume, 4 bytes. The purpose of those
    # structures is unknown.
    #    Solution:
    #     * I've made custom vars for types 13 and 14 - FEs are
    #     only from there
    #     * FF option now checks if the next byte is not FF
    # Case 2:
    # Variable 49 is color change. It contains 0xFF that's not an
    # option so we'll ignore it. It's probably better to make this
    # var pretty instead though.
    # Case 3:
    # In a bunch of German and French files instead of writing
    # item and NPC names as is, like in English and Japanese, they
    # refer to them through variables of types 32 and 33. Because
    # of that there can be FF after ((...)) so we're gonna ignore it.
    # TODO: Figure out how referencing works and make it pretty.
    $ignore_FF_counter = 0
    
try{

    for ($i = 0; $i -lt $ByteArray.Count; $i++) {
        while ( $depth_memory[-1] -and $i -eq ($depth_memory[-1] + $offset) ) {
            $depth_memory.RemoveAt($depth_memory.Count-1)
            if (-not $looking_for_02 -and $ByteArray[$i] -eq 0x03) {
                $ByteArray.RemoveAt($i)
                if ($ByteArray[$i-1] -ne 0x20) {
                    $ByteArray.InsertRange($i, [byte[]](0x20, 0x2F, 0x76, 0x61, 0x72, 0x3E)) # " /var>"
                    $offset += 5
                    $i += 6
                } else {
                    $ByteArray.InsertRange($i, [byte[]](0x2F, 0x76, 0x61, 0x72, 0x3E)) # "/var>"
                    $offset += 4
                    $i += 5
                }
                $ignore_FF_counter = 0; $type_byte = 0   # Case 3 - Reset
            } else {
                $ByteArray.InsertRange($i, [byte[]](0x29, 0x29, 0x20)) # ")) "
                switch ($type_byte) {   # Case 3 - Set up
                    0x32 { $ignore_FF_counter = 1; break }
                    0x33 { $ignore_FF_counter = 1; break }
                }
                $offset += 3
                $i += 3
            }
            $looking_for_02 = -not $looking_for_02
        }
        if ($looking_for_02) {
            if ($depth_memory[-1]) {
                $_next_02 = $ByteArray.IndexOf([byte]0x02, $i, $depth_memory[-1] + $offset - $i)
                $_next_0A = $ByteArray.IndexOf([byte]0x0A, $i, $depth_memory[-1] + $offset - $i)
            } else {
                $_next_02 = $ByteArray.IndexOf([byte]0x02, $i)
                $_next_0A = $ByteArray.IndexOf([byte]0x0A, $i)
            }
            $_comparison = ( $_next_02, $_next_0A ) | Measure-Object -Minimum -Maximum
            if ($_comparison.Minimum -eq -1) {
                if ($_comparison.Maximum -eq -1) {
                    if ($depth_memory[-1]) {
                        $i = $depth_memory[-1] + $offset - 1
                        continue
                    } else {
                        break
                    }
                } else {
                    $i = $_comparison.Maximum
                }
            } else {
                $i = $_comparison.Minimum
            }
        
            switch ($ByteArray[$i]) {
                0x02 {
                    $looking_for_02 = $false
                
                    $type_byte = $ByteArray[$i+1]
                    switch ($type_byte) {
                        # TODO: I should probably add here a way to set up a dynamic list of vars' types definitions
                        # Must output:
                        # * [byte[]]$var_string          - String represented in bytes
                        # * $replace_var = $true/$false  - Do we want to replace the whole var including 0x03 at the end?
                        0x10    {   # New line
                            # <var 10 /var> = `n (0x0A byte)
                            $var_string = [byte[]](0x0A)
                            $replace_var = $true
                            break
                        }
                        0x13    {   # Alternative text color change
                            # <var 13 FEFFRRGGBB /var> = <color2 #RRGGBB>
                            # <var 13 E9XX /var> = <color2 E9XX>
                            # <var 13 EC /var> = </color2>
                            switch ($ByteArray[$i+3]) {
                                0xFE {   # Start - Set RGB
                                    $_r = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+5] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+5] % 0x10) )
                                    )
                                    $_g = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+6] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+6] % 0x10) )
                                    )
                                    $_b = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+7] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+7] % 0x10) )
                                    )
                                    $var_string = [byte[]](
                                        0x3C, 0x63, 0x6F, 0x6C, 0x6F, 0x72, 0x32, 0x20, 0x23,   # "<color2 #RRGGBB>"
                                        $_r[0], $_r[1], $_g[0], $_g[1], $_b[0], $_b[1], 0x3E)
									
									$replace_var = $true
                                    break
                                }
                                0xE9 {   # Start - Set color from player parameter
                                    $_param = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+4] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+4] % 0x10) )
                                    )
                                    $var_string = [byte[]](
                                        0x3C, 0x63, 0x6F, 0x6C, 0x6F, 0x72, 0x32, 0x20,   # "<color2 E9XX>"
                                        0x45, 0x39, $_param[0], $_param[1], 0x3E)
									
									$replace_var = $true
                                    break
                                }
                                0xEC {   # End
                                    $var_string = [byte[]](0x3C, 0x2F, 0x63, 0x6F, 0x6C, 0x6F, 0x72, 0x32, 0x3E)  # "</color2>"
									$replace_var = $true
									break
                                }
								default {
									$ignore_FF_counter = 1
									$type_byte_hex = @(
										[char]( "{0:X}" -f [uint32][System.Math]::Floor($type_byte / 0x10) ),
										[char]( "{0:X}" -f [uint32]($type_byte % 0x10) )
									)
									$var_string = [byte[]](0x3C, 0x76, 0x61, 0x72, 0x20, $type_byte_hex[0], $type_byte_hex[1], 0x20) # "<var XX " where XX is variable type
									$replace_var = $false	
								}
                            }
                            break
                        }
                        0x14    {   # Alternative text glow change
                            # <var 14 FEFFRRGGBB /var> = <glow2 #RRGGBB>
                            # <var 14 EC /var> = </glow2>
                            switch ($ByteArray[$i+3]) {
                                0xFE {   # Start - Set RGB
                                    $_r = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+5] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+5] % 0x10) )
                                    )
                                    $_g = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+6] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+6] % 0x10) )
                                    )
                                    $_b = @(
                                        [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i+7] / 0x10) ),
                                        [char]( "{0:X}" -f [uint32]($ByteArray[$i+7] % 0x10) )
                                    )
                                    $var_string = [byte[]](
                                        0x3C, 0x67, 0x6C, 0x6F, 0x77, 0x32, 0x20, 0x23,   # "<glow2 #RRGGBB>"
                                        $_r[0], $_r[1], $_g[0], $_g[1], $_b[0], $_b[1], 0x3E)
									
									$replace_var = $true
                                    break
                                }
                                0xEC {   # End
                                    $var_string = [byte[]](0x3C, 0x2F, 0x67, 0x6C, 0x6F, 0x77, 0x32, 0x3E)  # "</glow2>"
									$replace_var = $true
                                }
								default {
									$ignore_FF_counter = 1
									$type_byte_hex = @(
										[char]( "{0:X}" -f [uint32][System.Math]::Floor($type_byte / 0x10) ),
										[char]( "{0:X}" -f [uint32]($type_byte % 0x10) )
									)
									$var_string = [byte[]](0x3C, 0x76, 0x61, 0x72, 0x20, $type_byte_hex[0], $type_byte_hex[1], 0x20) # "<var XX " where XX is variable type
									$replace_var = $false		
								}
                            }
                            break
                        }
                        0x49    {   # Text color change
                            # This doesn't make the text pretty and exists as a workaround for case 2.
                            $ignore_FF_counter = 1   # Case 2
                            $var_string = [byte[]](0x3C, 0x76, 0x61, 0x72, 0x20, 0x34, 0x39, 0x20) # "<var 49 "
                            $replace_var = $false
                            break
                        }
                        default {
                            # "<var XX " and the rest will be filled up by the function
                            $type_byte_hex = @(
                                [char]( "{0:X}" -f [uint32][System.Math]::Floor($type_byte / 0x10) ),
                                [char]( "{0:X}" -f [uint32]($type_byte % 0x10) )
                            )
                            $var_string = [byte[]](0x3C, 0x76, 0x61, 0x72, 0x20, $type_byte_hex[0], $type_byte_hex[1], 0x20) # "<var XX " where XX is variable type
                            $replace_var = $false
                        }
                    }
                
                    # First byte of the size
                    switch ($ByteArray[$i+2]) {
                        0xF2 {
                            if ([System.BitConverter]::IsLittleEndian) {
                                $size = [System.BitConverter]::ToUInt16($ByteArray[($i+4)..($i+3)], 0)
                            } else {
                                $size = [System.BitConverter]::ToUInt16($ByteArray[($i+3)..($i+4)], 0)
                            }
                            $depth_memory.Add( $i + $size+5 - $offset )
                            $ByteArray.RemoveRange($i, 5)
                            $ByteArray.InsertRange($i, $var_string)
                            $offset += $var_string.Count - 5
                            break
                        }
                        0xF1 {
                            $size = $ByteArray[$i+3] * 0x100
                            $depth_memory.Add( $i + $size+4 - $offset )
                            $ByteArray.RemoveRange($i, 4)
                            $ByteArray.InsertRange($i, $var_string)
                            $offset += $var_string.Count - 4
                            break
                        }
                        0xF0 {
                            $size = $ByteArray[$i+3]
                            $depth_memory.Add( $i + $size+4 - $offset )
                            $ByteArray.RemoveRange($i, 4)
                            $ByteArray.InsertRange($i, $var_string)
                            $offset += $var_string.Count - 4
                        }
                        default {
                            $size = $ByteArray[$i+2] - 1
                            if ($replace_var) {
                                $ByteArray.RemoveRange($i, $size+4)
                                $ByteArray.InsertRange($i, $var_string)
                                $offset += $var_string.Count - $size - 4
                                $looking_for_02 = $true
                            } else {
                                $depth_memory.Add( $i + $size+3 - $offset )
                                $ByteArray.RemoveRange($i, 3)
                                $ByteArray.InsertRange($i, $var_string)
                                $offset += $var_string.Count - 3
                            }
                        }
                    }
                    $i += $var_string.Count - 1
                    break
                }
                0x0A {
                    $ByteArray.RemoveAt($i)
                    $ByteArray.InsertRange($i, [byte[]](0x3C, 0x6E, 0x6C, 0x3E)) # "<nl>"
                    $offset += 3
                    $i += 2
                }
            }
        } elseif ( $ByteArray[$i] -eq 0xFF -and $ByteArray[$i+1] -ne 0xFF -and -not $ignore_FF_counter ) {
            $looking_for_02 = $true
			
            # First byte of the size
            switch ($ByteArray[$i+1]) {
                0xF2 {
                    if ([System.BitConverter]::IsLittleEndian) {
                        $size = [System.BitConverter]::ToUInt16($ByteArray[($i+3)..($i+2)], 0)
                    } else {
                        $size = [System.BitConverter]::ToUInt16($ByteArray[($i+2)..($i+3)], 0)
                    }
                    $depth_memory.Add( $i+4 + $size - $offset )
                    $ByteArray.RemoveRange($i, 4)
                    $offset -= 4
                    break
                }
                0xF1 {
                    $size = $ByteArray[$i+2] * 0x100
                    $depth_memory.Add( $i+3 + $size - $offset )
                    $ByteArray.RemoveRange($i, 3)
                    $offset -= 3
                    break
                }
                0xF0 {
                    $size = $ByteArray[$i+2]
                    $depth_memory.Add( $i+3 + $size - $offset )
                    $ByteArray.RemoveRange($i, 3)
                    $offset -= 3
                }
                default {
                    $size = $ByteArray[$i+1] - 1
                    $depth_memory.Add( $i+2 + $size - $offset )
                    $ByteArray.RemoveRange($i, 2)
                    $offset -= 2
                }
            }
			
            if ($ByteArray[$i-1] -eq 0x20) {   # " "
                $ByteArray.InsertRange($i, [byte[]](      0x28, 0x28))   #  "(("
                $offset += 2
                $i += 1
            } else {
                $ByteArray.InsertRange($i, [byte[]](0x20, 0x28, 0x28))   # " (("
                $offset += 3
                $i += 2
            }
        } else {
            if ($ByteArray[$i] -eq 0xFF -and $ignore_FF_counter) { $ignore_FF_counter-- }
            $byte_hex = [byte[]]@( 
                [char]( "{0:X}" -f [uint32][System.Math]::Floor($ByteArray[$i] / 0x10) ),
                [char]( "{0:X}" -f [uint32]($ByteArray[$i] % 0x10) )
            )
            $ByteArray.RemoveAt($i)
            $ByteArray.InsertRange($i, $byte_hex)
            $offset += 1
            $i += 1
        }
    }
}
catch {
	$_
}
    
    return ,$ByteArray
}

function Convert-TagsToVariables
{
    ################################################################
    #.Synopsis
    # Convert variable tags that were generated by EXDtoCSV script
    # into 0x02..0x03 variables. Output is ByteArray.
    #.Parameter String
    # Target string.
    #.Example
    # [String] $x = '<var 08 E905 ((а)) (()) /var>'
    # Convert-TagsToVariables $x
    #
    # @(0x02,0x08,0x09,0xE9,0x05,0xFF,0x03,0xD0,0xB0,0xFF,0x01,0x03)
    ################################################################
    [CmdletBinding()] Param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)] [String] $String
    )

    # It'd be a pain to correctly recognize `n later so instead we'll do this.
    $String = $String.Replace("`n", '<br>')

    # It's much easier to operate with the string so we're gonna convert an array to hex string.
    $HexString = $(Convert-ByteArrayToHexString $([System.Text.Encoding]::UTF8.GetBytes($String))) -replace '^0x',''

    # <br>
    $memory = $(Select-String -InputObject $HexString -Pattern '3C62723E' -AllMatches).Matches
    foreach ($match in $memory) {
        $HexString = $HexString.Remove($match.Index, 8).Insert($match.Index, '02100103')
    }
    
    # String size will change so indexes will not match anymore.
    # Working on the string from the end to the start mitigates this issue.
    # <tab>
    $memory = $(Select-String -InputObject $HexString -Pattern '3C7461623E' -AllMatches).Matches
    if ($memory) { [array]::Reverse($memory) }
    foreach ($match in $memory) {
        $HexString = $HexString.Remove($match.Index, 10).Insert($match.Index, '00')
    }
    # Add the last EOL byte
    $HexString = $HexString.Insert($HexString.Length, '00')

    # <nl>
    $memory = $(Select-String -InputObject $HexString -Pattern '3C6E6C3E' -AllMatches).Matches
    if ($memory) { [array]::Reverse($memory) }
    foreach ($match in $memory) {
        $HexString = $HexString.Remove($match.Index, 8).Insert($match.Index, '0A')
    }

    # <color2>
    $memory = $(Select-String -InputObject $HexString -Pattern '636F6C6F7232' -AllMatches).Matches
    if ($memory) { [array]::Reverse($memory) }
    foreach ($match in $memory) {
        switch ($HexString.Substring($match.Index-2, 2)) {
            '2F' {  # "/"
                $HexString = $HexString.Remove($match.Index-4, 18).Insert($match.Index-4, '021302EC03')
                break
            }
            '3C' {  # "<"
                switch ($HexString.Substring($match.Index+14, 2)) {
                    '23' {  # "#"
                        $_rgb = $HexString.Substring($match.Index+16, 12)
                        $_r = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(0, 2)), [char][uint32]$('0x' + $_rgb.Substring(2, 2))
                        $_g = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(4, 2)), [char][uint32]$('0x' + $_rgb.Substring(6, 2))
                        $_b = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(8, 2)), [char][uint32]$('0x' + $_rgb.Substring(10, 2))
                        $HexString = $HexString.Remove($match.Index-2, 32).Insert($match.Index-2,
                            ("021306FEFF{0}{1}{2}03" -f $_r, $_g, $_b) )
                        break
                    }
                    '45' {  # "E"
                        $_param = "{0}{1}" -f [char][uint32]$('0x' + $HexString.Substring($match.Index+18, 2)),
                            [char][uint32]$('0x' + $HexString.Substring($match.Index+20, 2))
                        $HexString = $HexString.Remove($match.Index-2, 26).Insert($match.Index-2, "021303E9{0}03" -f $_param)
                    }
                }
            }
        }
    }

    # <glow2>
    $memory = $(Select-String -InputObject $HexString -Pattern '676C6F7732' -AllMatches).Matches
    if ($memory) { [array]::Reverse($memory) } # See explanation above
    foreach ($match in $memory) {
        switch ($HexString.Substring($match.Index-2, 2)) {
            '2F' {  # "/"
                $HexString = $HexString.Remove($match.Index-4, 16).Insert($match.Index-4, '021402EC03')
                break
            }
            '3C' {  # "<"
                $_rgb = $HexString.Substring($match.Index+14, 12)
                $_r = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(0, 2)), [char][uint32]$('0x' + $_rgb.Substring(2, 2))
                $_g = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(4, 2)), [char][uint32]$('0x' + $_rgb.Substring(6, 2))
                $_b = "{0}{1}" -f [char][uint32]$('0x' + $_rgb.Substring(8, 2)), [char][uint32]$('0x' + $_rgb.Substring(10, 2))
                $HexString = $HexString.Remove($match.Index-2, 30).Insert($match.Index-2,
                    ("021406FEFF{0}{1}{2}03" -f $_r, $_g, $_b) )
            }
        }
    }


    $start_memory = [System.Collections.Generic.List[int]]::new()
    $looking_for_var = $true

    for ($i = 0; $i -lt $HexString.Length-8; $i += 2) {
        if ($looking_for_var) {
            # TODO: Use IndexOf here to jump on '<var ' or '))', or to break the function
            switch -wildcard ($HexString.Substring($i, 10)) {
                '3C76617220' {  # "<var "
                    $looking_for_var = $false
                    $start_memory.Add($i) # Remember position for later. String manipulation will happen at the ends of vars and options
                    $i += 12 # Skipping over the type too
                    break
                }
                "292929*" {  # ")))"
                    # Assume that the first ')' is part of the string and skip it
                    break
                }
                "2929*" {  # "))"
                    if ($start_memory[-1]) {
                        $looking_for_var = $false
                        $HexString = $HexString.Remove($i, 4)  # 4 is length of "))"
                        $size = ($i - $start_memory[-1] - 4) / 2   # 4 is length of "(("
                        # Here we're aligning $i to the end of FF option minus 2
                        if (($size -gt 0) -and ($size % 0x100 -eq 0)) {
                            $HexString = $HexString.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF1{0:X2}" -f ($size / 0x100))
                        } elseif ($size -le 214) {
                            $HexString = $HexString.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FF{0:X2}" -f ($size+1))
                            $i -= 2
                        } elseif ($size -le 256) {
                            $HexString = $HexString.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF0{0:X2}" -f $size)
                        } else {
                            $HexString = $HexString.Remove($start_memory[-1], 4).Insert($start_memory[-1], "FFF2{0:X4}" -f $size)
                            $i += 2
                        }
                        $start_memory.RemoveAt($start_memory.Count-1)
                    }
                    break
                }
                "20E28094*" {  # " —" (general space with em-dash)
                    $HexString = $HexString.Remove($i, 2).Insert($i, "C2A0")  # Change general space to non-breakable space
                    $i += 2
                }
            }
        } else {
            switch -wildcard ($HexString.Substring($i, 10)) {
                '2F7661723E' {  # "/var>"
                    $looking_for_var = $true
                    $HexString = $HexString.Remove($i, 10).Insert($i, '03')

                    $type_hex = $HexString.Substring($start_memory[-1]+10, 4)
                    $type = "{0}{1}" -f [char][uint32]$('0x' + $type_hex.Substring(0, 2)), [char][uint32]$('0x' + $type_hex.Substring(2, 2))
                    $size = ($i - $start_memory[-1] - 14) / 2 + 1   # 14 is length of "<var XX"; +1 is 03 in the end
                    if (($size -gt 1) -and (($size - 1) % 0x100 -eq 0)) {
                        $HexString = $HexString.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F1{1:X2}" -f $type, (($size-1) / 0x100) ))
                        $i -= 6 
                    } elseif ($size -le 215) {
                        $HexString = $HexString.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}{1:X2}" -f $type, $size) )
                        $i -= 8
                    } elseif ($size -le 257) {
                        $HexString = $HexString.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F0{1:X2}" -f $type, ($size-1) ))
                        $i -= 6
                    } else {
                        $HexString = $HexString.Remove($start_memory[-1], 14).Insert($start_memory[-1], $("02{0}F2{1:X4}" -f $type, ($size-1) ))
                        $i -= 4
                    }
                    $start_memory.RemoveAt($start_memory.Count-1)
                    break
                }
                "2828*" {  # "(("
                    $looking_for_var = $true
                    $start_memory.Add($i) # Same as for '<var '
                    $i += 2
                    break
                }
                "20*" {  # " "
                    $HexString = $HexString.Remove($i, 2)
                    $i -= 2
                }
                default {
                    $byte_hex = $HexString.Substring($i, 4)
                    $byte = "{0}{1}" -f [char][uint32]$('0x' + $byte_hex.Substring(0, 2)), [char][uint32]$('0x' + $byte_hex.Substring(2, 2))
                    $HexString = $HexString.Remove($i, 4).Insert($i, $byte)
                }
            }
        }
    }

    try {
        $ByteArray = Convert-HexStringToByteArray $HexString
    }
    catch {
        $_
    }
    return $ByteArray
}

function Remove-BomFromFile($Path)
{
    $Content = Get-Content $Path -Raw
    [System.IO.File]::WriteAllLines($Path, $Content)
}

function Search-API {
    param (
        # Weblate server base URL
        [string] $URI,
        # Authorization headers
        [hashtable] $h,
        # Component name
        [string] $c,
        # Language
        [string] $l,
        # Search string
        [string] $q
    )
    $query = [System.Web.HTTPUtility]::UrlEncode($q)

    $reply = Invoke-RestMethod -Method Get `
        -Headers $h -Uri "https://$URI/api/translations/ffxiv-translation/$c/$l/units/?q=$query"
    return $reply
}

function Search-Web {
    param (
        # Weblate server base URL
        [string] $URI,
        # Search string
        [string] $q
    )
    # Currently there's no API for global search so we'll do it the slow and dirty way
    # and parse the Web page instead.
    $web_reply = Invoke-WebRequest "https://$URI/search/?q=$q" -UseBasicParsing
    # Getting a link to the component of the first search result
    $result = "https://$URI{0}" -f $web_reply.Links[43].href
    # Sleeping for a bit because web search is rate limited
    Start-Sleep -Seconds 2

    return $result
}
