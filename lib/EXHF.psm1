# This file contains EXHF class and its supplementary classes

class EXHF {
    [string] $Path

    static [int32] $Signature = 0x45584846 # "EXHF"
    static [int16] $Version = 0x0003
    [int16] $SizeOfDatasetChunk
    [byte[]] $Unknown1 # uint16 in big-endian; use GetUnknown1() to get value
    [byte[]] $Unknown2 # uint32 in big-endian; use GetUnknown2() to get value
    [int32] $NumberOfEntries
    [System.Collections.Generic.List[DatasetUnit]] $DatasetTable = @()
    [PageUnit[]] $PageTable
    $LangTable = [LangUnit[]]::new(8)  # Lang_CodeByte.Count + 1

    [int[]] $StringDatasetOffsets

    # FileInfo object is also accepted since it has $Path property
    EXHF([string]$Path) {
        $ExhBytes = [System.IO.File]::ReadAllBytes($Path)
        $this.Path = $Path
        if ([System.BitConverter]::ToUInt32($ExhBytes[0x03..0x00], 0) -ne [EXHF]::Signature) {
            throw [System.IO.InvalidDataException]::new(
                "Incorrect format: File signature is not EXHF."
            )
        }
        $ver = [System.BitConverter]::ToUInt16($ExhBytes[0x05..0x04], 0)
        if ($ver -ne [EXHF]::Version) {
            Write-Warning "Unexpected EXH version: {0} instead of {1}.`n`tFile: $Path" -f $ver, [EXHF]::Version
        }
        $this.SizeOfDatasetChunk = [System.BitConverter]::ToUInt16($ExhBytes[0x07..0x06], 0)
        $NumberOfDatasets =        [System.BitConverter]::ToUInt16($ExhBytes[0x09..0x08], 0)
        $NumberOfPages =           [System.BitConverter]::ToUInt16($ExhBytes[0x0B..0x0A], 0)
        $NumberOfLangCodes =       [System.BitConverter]::ToUInt16($ExhBytes[0x0D..0x0C], 0)
        $this.Unknown1 =           $ExhBytes[0x0E..0x0F]
        $this.Unknown2 =           $ExhBytes[0x10..0x13]
        $this.NumberOfEntries =    [System.BitConverter]::ToUInt32($ExhBytes[0x17..0x14], 0)
        foreach ($i in (0..($NumberOfDatasets-1))) {
            $this.DatasetTable.Add(
                [DatasetUnit]::new([System.BitConverter]::ToUInt16($ExhBytes[(0x21 + $i*4)..(0x20 + $i*4)], 0), [System.BitConverter]::ToUInt16($ExhBytes[(0x23 + $i*4)..(0x22 + $i*4)], 0))
            )
        }
        $offset = 0x20 + $NumberOfDatasets * 4
        $this.PageTable = foreach ($i in (0..($NumberOfPages-1))) {
            [PageUnit]::new(
                $this,
                [System.BitConverter]::ToUInt32($ExhBytes[($offset + 3 + $i*8)..($offset + $i*8)], 0),
                [System.BitConverter]::ToUInt32($ExhBytes[($offset + 7 + $i*8)..($offset + 4 + $i*8)], 0)
            )
        }
        $offset += $NumberOfPages * 8
        foreach ($i in (0..($NumberOfLangCodes-1))) {
            $this.LangTable[$i+1] = [LangUnit]::new(
                [System.BitConverter]::ToUInt16($ExhBytes[($offset + $i*2)..($offset + 1 + $i*2)], 0)
            )
        }
    }


    [string] GetBaseName() {
        return $(Split-Path $this.Path -Leaf) -replace '\.exh',''
    }


    [int16] GetNumberOfDatasets() {
        return $this.DatasetTable.Count
    }

    [int16] GetNumberOfPages() {
        return $this.PageTable.Count
    }

    [int16] GetNumberOfLangs() {
        return $this.LangTable.Count
    }

    [int16] GetUnknown1() {
        return [System.BitConverter]::ToUInt16($this.Unknown1[1..0], 0)
    }

    [int32] GetUnknown2() {
        return [System.BitConverter]::ToUInt32($this.Unknown2[3..0], 0)
    }


    [DatasetUnit] GetDataset([int]$Number) {
        return $this.DatasetTable[$Number]
    }

    # Make sure to create a separate modded EXH variable first
    [void] AddDataset([Dataset_NameByte]$Type, $ExdRef) {
        $Type = [uint16]$Type
        if ([System.Enum]::IsDefined([Dataset_NameByte], $Type) -eq $false) {
            throw [System.Management.Automation.PSArgumentException]::new(
                "Unknown Dataset type {0}." -f $Type
            )
        }
        if ([DatasetUnit]::GetRequiredBytesByType($Type) -eq 0) {
            throw [System.Management.Automation.PSNotImplementedException]::new(
                "The amount of bytes that will take type {0} ({1}) is unknown." -f $Type, [DatasetUnit]::GetTypeNameByType($Type)
            )
        }
        $this.DatasetTable.Add(
            [DatasetUnit]::new($Type, $this.SizeOfDatasetChunk)
        )
        $new_dataset_size = [DatasetUnit]::GetRequiredBytesByType($this.GetDataset(-1).get_Type())
        $this.SizeOfDatasetChunk += $new_dataset_size
        if ($null -ne $this.StringDatasetOffsets -and $Type -eq [Dataset_NameByte]::string) {
            $this.StringDatasetOffsets += $this.GetDataset(-1).get_Offset()
        }
        foreach ($DataRow in $ExdRef.DataRowTable.GetEnumerator()) {
            if ($Type -eq [Dataset_NameByte]::string) {
                [int32] $new_string_offset = [array]::IndexOf($DataRow.Value.StringBytes, [byte]0x00, $DataRow.Value.GetStringIndex(-2)) + 1
                # If there's no 0x00 byte for our new string then add one
                if ( $null -eq $DataRow.Value.StringBytes[$new_string_offset] ) {
                    $DataRow.Value.StringBytes += [byte[]](0x00)
                }
                $DataRow.Value.DataBytes += [System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($new_string_offset) )
            } else {
                $DataRow.Value.DataBytes += [byte[]](0x00) * $new_dataset_size
            }
            $DataRow.Value.AlignChunk()
        }
    }

    [int[]] GetStringDatasetOffsets() {
        if ($null -eq $this.StringDatasetOffsets) {
            $this.StringDatasetOffsets = foreach ($Dataset in $this.DatasetTable) {
                if ($Dataset.Type -eq 0x00) { $Dataset.Offset }
            }
            $this.StringDatasetOffsets = $this.StringDatasetOffsets | Sort-Object
        }
        return $this.StringDatasetOffsets
    }


    [PageUnit] GetPage([int]$Number) {
        return $this.PageTable[$Number]
    }

    [LangUnit] GetLang([Lang_CodeByte]$Lang) {
        return $this.LangTable[$Lang]
    }


    [void] Export([string]$Destination) {
        [System.Collections.Generic.List[byte]] $output = @()
        # Header
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder([EXHF]::Signature) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder([EXHF]::Version) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($this.get_SizeOfDatasetChunk()) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($this.GetNumberOfDatasets()) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($this.GetNumberOfPages()) ))
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($this.GetNumberOfLangs()) ))
        $output.AddRange($this.Unknown1)
        $output.AddRange($this.Unknown2)
        $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($this.get_NumberOfEntries()) ))
        $output.AddRange([byte[]](0x00) * 8)
        # Dataset table
        foreach ($Dataset in $this.DatasetTable) {
            $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($Dataset.get_Type()) ))
            $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($Dataset.get_Offset()) ))
        }
        # Page table
        foreach ($Page in $this.PageTable) {
            $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($Page.get_Entry()) ))
            $output.AddRange([System.BitConverter]::GetBytes( [ipaddress]::HostToNetworkOrder($Page.get_Size()) ))
        }
        # Language table
        foreach ($LangByte in $this.LangTable) {
            if ($null -ne $LangByte) {
                $output.AddRange([System.BitConverter]::GetBytes($LangByte.get_Byte()))
            }
        }
        # Done
        Set-Content -Value $output -Encoding Byte -Path $Destination
    }
}

enum Dataset_NameByte {
    string =   0x00
    bool =     0x01
    byte =     0x02
    ubyte =    0x03
    short =    0x04
    ushort =   0x05
    int =      0x06
    uint =     0x07
    float =    0x09
    int_x4 =   0x0B
    bitflags = 0x19
}

enum Dataset_NameRequiredBytes {
    string =   4
    bool =     1
    byte =     1
    ubyte =    1
    short =    2
    ushort =   2
    int =      4
    uint =     4
    float =    4
    int_x4 =   8
    bitflags = 0
}

class DatasetUnit {
    [int16] $Type
    [int16] $Offset

    DatasetUnit([uint16]$Type, [uint16]$Offset) {
        $this.Type = $Type
        $this.Offset = $Offset
    }

    static [string] GetTypeNameByType([int]$Type) {
        return [Dataset_NameByte]$Type
    }
    
    static [int] GetTypeByTypeName([string]$TypeName) {
        return [Dataset_NameByte]::$($TypeName)
    }

    static [int] GetRequiredBytesByType([int]$Type) {
        return [Dataset_NameRequiredBytes]::$([DatasetUnit]::GetTypeNameByType($Type))
    }


    [string] get_TypeName() {
        return [DatasetUnit]::GetTypeNameByType($this.Type)
    }

    [int] get_RequiredBytes() {
        return [DatasetUnit]::GetRequiredBytesByType($this.Type)
    }
}

class PageUnit {
    [EXHF] $ExhRef
    [int32] $Entry
    [int32] $Size

    PageUnit([EXHF]$Exh, [uint32]$Entry, [uint32]$Size) {
        $this.ExhRef = $Exh
        $this.Entry = $Entry
        $this.Size = $Size
    }
}

enum Lang_CodeByte {
    ja  = 1
    en  = 2
    de  = 3
    fr  = 4
    chs = 5
    cht = 6
    ko  = 7
}

class LangUnit {
    [int16] $Byte

    LangUnit([uint16]$LangByte) {
        $this.Byte = $LangByte
    }

    static [string] get_LangCodeByByte([int]$LangByte) {
        return [Lang_CodeByte].GetEnumName($LangByte)
    }

    static [int] get_LangByteByCode([string]$LangCode) {
        return [Lang_CodeByte]::$($LangCode)
    }

    [string] get_Code() {
        return [LangUnit]::get_LangCodeByByte($this.Byte)
    }
}
