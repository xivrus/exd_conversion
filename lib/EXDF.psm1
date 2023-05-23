# This file contains EXDF class and its supplementary classes
using module .\EXHF.psm1
using namespace System.Buffers.Binary

class EXDF {
    [EXHF] $ExhRef
    [PageUnit] $PageRef
    [LangUnit] $LangRef
    [string] $Path

    static [int32] $Signature = 0x45584446 # "EXDF"
    static [int16] $Version = 0x0002
    [byte[]] $Unknown # int16 in big-endian; use GetUnknown() to get actual value
    $DataRowTable = [System.Collections.Generic.Dictionary[int,DataRowUnit]]::new()

    # Passing FileInfo object is also accepted
    EXDF([PageUnit]$Page, [LangUnit]$Lang, [string]$Path) {
        $ExdBytes = [System.IO.File]::ReadAllBytes($Path)
        if ([System.BitConverter]::ToUInt32($ExdBytes[0x03..0x00], 0) -ne [EXDF]::Signature) {
            throw [System.IO.InvalidDataException]::new(
                "Incorrect format: File signature is not EXHD."
            )
        }
        $this.LangRef = $Lang
        $this.PageRef = $Page
        $this.ExhRef = $Page.ExhRef
        $this.Path = $Path
        $ver = [System.BitConverter]::ToUInt16($ExdBytes[0x05..0x04], 0)
        if ($ver -ne [EXDF]::Version) {
            Write-Warning "Unexpected EXD version: {0} instead of {1}`n`tFile: $Path" -f $ver, [EXDF]::Version
        }
        $this.Unknown = $ExdBytes[0x06..0x07]
        if ($this.ExhRef.GetNumberOfPages() -eq 1) {
            # There are some files that have incorrect page size due to skipped indexes.
            # The worst offender is 'addon'. For such files we'll get the true amount
            # from the offset table size.
            $total_entries = [System.BitConverter]::ToUInt32($ExdBytes[0x0B..0x08], 0) / 8
        } else {
            $total_entries = $this.PageRef.get_Size()
        }
        if ($total_entries -gt 0) {
            foreach ($i in (0..$($total_entries - 1))) {
                $offset = [System.BitConverter]::ToUInt32($ExdBytes[(0x27 + $i * 8)..(0x24 + $i * 8)], 0)
                $size = [System.BitConverter]::ToUInt32($ExdBytes[($offset + 3)..($offset)], 0)
                try {
                $this.DataRowTable.Add(
                    [int] [System.BitConverter]::ToUInt32($ExdBytes[(0x23 + $i * 8)..(0x20 + $i * 8)], 0),
                    [DataRowUnit]::new(
                        $this.ExhRef,
                        $size,
                        $ExdBytes[($offset + 4)..($offset + 5)],
                        $ExdBytes[($offset + 6)..($offset + 5 + $this.ExhRef.get_SizeOfDatasetChunk())],
                        $ExdBytes[($offset + 6 + $this.ExhRef.get_SizeOfDatasetChunk())..($offset + 5 + $size)]
                    )
                )
                }
                catch {
                    $_
                }
            }
        }
    }
    # Create path assuming this EXD is in the same folder as EXH
    EXDF([PageUnit]$Page, [LangUnit]$Lang) {
        $this.LangRef = $Lang
        $this.PageRef = $Page
        $this.ExhRef = $Page.ExhRef
        EXDF("{0}") -f $(
            $this.ExhRef.Path -replace '\.exh',("_{0}_{1}.exd" -f
                $this.PageRef.get_Entry(),
                $this.LangRef.get_Code())
        )
    }


    [int] GetUnknown() {
        return [System.BitConverter]::ToUInt16($this.Unknown[1..0], 0)
    }

    [byte[]] GetDataBytes([int]$Index) {
        return $this.DataRowTable.$Index.DataBytes
    }

    [byte[]] GetStringBytes([int]$Index) {
        return $this.DataRowTable.$Index.StringBytes
    }

    # This method outputs up to the last 0x00 byte
    [byte[]] GetStringBytesFiltered([int]$Index) {
        return $this.DataRowTable.$Index.GetStringBytesFiltered()
    }

    [void] SetStringBytes([int]$Index, [byte[]]$StringBytes) {
        $this.DataRowTable.$Index.SetStringBytes($StringBytes)
    }

    [void] ExportBIN([string]$Destination) {
        [System.Collections.Generic.List[byte]] $output = @()
        foreach ($DataRow in $this.DataRowTable.GetEnumerator()) {
            $output.AddRange($DataRow.Value.DataBytes)
        }
        Set-Content -Value $output -Encoding Byte -Path $Destination
    }

    [void] ExportEXD([string]$Destination) {
        [System.Collections.Generic.List[byte]] $output = @()
        # Header except DataSectionSize
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder([EXDF]::Signature) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder([EXDF]::Version) ))
        $output.AddRange($this.Unknown)
        $offset_table_size = $this.DataRowTable.Count * 8
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($offset_table_size) ))
        $output.AddRange([byte[]](0x00) * 20)  # 0x0C..0x0F is DataSectionSize, it will be filled later
        # Offset table + Data section
        $data_current_index = $output.Count + $offset_table_size
        $offset_current_index = $output.Count
        foreach ($DataRow in $this.DataRowTable.GetEnumerator()) {
            $output.InsertRange($offset_current_index, [System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($DataRow.Key) ))
            $output.InsertRange($offset_current_index + 4, [System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($data_current_index) ))
            $offset_current_index += 8
            $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($DataRow.Value.get_SizeOfChunk()) ))
            $output.AddRange($DataRow.Value.Unknown)
            $output.AddRange($DataRow.Value.DataBytes)
            $output.AddRange($DataRow.Value.StringBytes)
            $data_current_index += $DataRow.Value.get_SizeOfChunk() + 6  # 4 bytes for SizeOfChunk + 2 bytes for Unknown
        }
        # Calculate and fill DataSectionSize; 32 is header size
        $data_section_size = [System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($output.Count - $offset_table_size - 32) )
        # For some reason CopyTo() doesn't work with [List<>]
        # so I'll do this the old-fashioned way
        foreach ($i in (0..3)) {
            $output[(0x0C + $i)] = $data_section_size[$i]
        }
        Set-Content -Value $output -Path $Destination -AsByteStream
    }
}

class DataRowUnit {
    [EXHF] $ExhRef
    [int32] $SizeOfChunk
    [byte[]] $Unknown  # int16 in big-endian; use GetUnknown() to get value
    [byte[]] $DataBytes
    [byte[]] $StringBytes

    DataRowUnit([EXHF]$ExhRef, [uint32]$s, [byte[]]$u, [byte[]]$d, [byte[]]$str) {
        $this.ExhRef = $ExhRef
        $this.SizeOfChunk = $s
        $this.Unknown = $u
        $this.DataBytes = $d
        $this.StringBytes = $str
    }

    [int] GetUnknown() {
        return [System.BitConverter]::ToUInt16($this.Unknown[1..0])
    }

    [int] GetStringIndex([int]$StrDatasetNum) {
        return [BitConverter]::ToUInt32($this.DataBytes[
            ($this.ExhRef.GetStringDatasetOffsets()[$StrDatasetNum] + 3)..($this.ExhRef.GetStringDatasetOffsets()[$StrDatasetNum])
        ], 0)
    }

    [byte[]] GetStringBytesFiltered() {
        if ($this.ExhRef.GetStringDatasetOffsets().Count -eq 0) { return [byte[]]@() }
        return $this.StringBytes[0..([array]::IndexOf(
                $this.StringBytes,
                [byte]0x00,
                $this.GetStringIndex(-1)
            ))]
    }

    # Align the whole chunk to 0x04 bytes if necessary; 2 is $this.Unknown.Count
    [void] AlignChunk() {
        $chunk_size = $this.DataBytes.Count + $this.StringBytes.Count
        if ($this.SizeOfChunk -ne $chunk_size) {
            if ($chunk_size % 4 -ne 2) {
                $this.StringBytes += [byte[]]@(0x00) * (4 - ($chunk_size + 2) % 4)
            }
            $this.SizeOfChunk = $this.DataBytes.Count + $this.StringBytes.Count
        }
    }

    # The input is expected to have the last 0x00 byte
    [void] SetStringBytes([byte[]]$StringBytes) {
        $this.StringBytes = $StringBytes
        # Don't change string dataset #0, it's always 0x00; start changing only from str. dataset #1
        for ($i = 1; $i -lt $this.ExhRef.GetStringDatasetOffsets().Count; $i++) {
            [System.BitConverter]::GetBytes(
                [array]::IndexOf($StringBytes, [byte]0x00, $this.GetStringIndex($i-1)) + 1
            )[3..0].CopyTo(
                $this.DataBytes,
                $this.ExhRef.GetStringDatasetOffsets()[$i]
            )
        }
        $this.AlignChunk()
    }
}
