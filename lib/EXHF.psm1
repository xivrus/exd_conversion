# This file contains EXHF class and its supplementary classes
using namespace System.Buffers.Binary

class EXHF {
    [string] $Path

    static [uint32] $Signature = 0x45584846 # "EXHF"
    static [uint16] $Version = 0x0003
    [uint16] $SizeOfDatasetChunk
    [uint16] $Unknown1 # use GetUnknown1() to get value
    [uint32] $Unknown2 # use GetUnknown2() to get value
    [uint32] $NumberOfEntries
	# $DatasetTable be a dynamic array for the ability to add more datasets
    [System.Collections.Generic.List[DatasetUnit]] $DatasetTable = @()
    [PageUnit[]] $PageTable
	# I don't really know how to properly implement languages
    $LangTable = [LangUnit[]]::new(8)

    [int[]] $StringDatasetOffsets

    # FileInfo object is also accepted since it has $Path property
    EXHF([string]$Path) {
		$stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open)
		$reader = [System.IO.BinaryReader]::new($stream)

        $this.Path = $Path
		$sig = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
        if ($sig -ne [EXHF]::Signature) {
            throw [System.IO.InvalidDataException]::new(
                "Incorrect format: File signature is not EXHF."
            )
        }
        $ver = [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        if ($ver -ne [EXHF]::Version) {
            Write-Warning "Unexpected EXH version: {0} instead of {1}.`n`tFile: $Path" -f $ver, [EXHF]::Version
        }
        $this.SizeOfDatasetChunk = [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        $NumberOfDatasets =        [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        $NumberOfPages =           [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        $NumberOfLangCodes =       [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        $this.Unknown1 =           [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        $this.Unknown2 =           [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
        $this.NumberOfEntries =    [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
        
		$null = $reader.ReadBytes(8)

		foreach ($i in (1..$NumberOfDatasets)) {
            $this.DatasetTable.Add(
				[DatasetUnit]::new(
					[BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) ),
					[BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
				)
            )
        }
        $this.PageTable = foreach ($i in (1..$NumberOfPages)) {
            [PageUnit]::new(
                $this,
                [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) ),
                [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
            )
        }
        foreach ($i in (1..$NumberOfLangCodes)) {
            $this.LangTable[$i] = [LangUnit]::new(
                $reader.ReadUInt16()
            )
		}

		$reader.Dispose()
		$stream.Dispose()
    }


    [string] GetBaseName() {
        return $(Split-Path $this.Path -Leaf) -replace '\.exh',''
    }

    [uint16] GetNumberOfDatasets() {
        return $this.DatasetTable.Count
    }

    [uint16] GetNumberOfPages() {
        return $this.PageTable.Count
    }

    [uint16] GetNumberOfLangs() {
        return $this.LangTable.Count
    }

    [uint16] GetUnknown1() {
        return $this.Unknown1
    }

    [uint32] GetUnknown2() {
        return $this.Unknown2
    }


    [DatasetUnit] GetDataset([int]$Number) {
        return $this.DatasetTable[$Number]
    }

    # Make sure to create a separate modded EXH variable first
	# TODO: Needs update since BinaryReader integration
	# TODO: Also I never tested it
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

    [LangUnit] GetLang([Lang_CodeValue]$Lang) {
        return $this.LangTable[$Lang]
    }


    [void] Export([string]$Destination) {
		$stream = [System.IO.FileStream]::new($Destination, [System.IO.FileMode]::Create)
		$writer = [System.IO.BinaryWriter]::new($stream)
		$bytes_uint32 = [byte[]](0x00) * 4
		$bytes_uint16 = [byte[]](0x00) * 2
        # Header
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, [EXHF]::Signature);              $writer.Write($bytes_uint32)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, [EXHF]::Version);                $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.get_SizeOfDatasetChunk()); $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.GetNumberOfDatasets());    $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.GetNumberOfPages());       $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.GetNumberOfLangs());       $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.Unknown1);                 $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $this.Unknown2);                 $writer.Write($bytes_uint32)
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $this.get_NumberOfEntries());    $writer.Write($bytes_uint32)
        $writer.Write([byte[]](0x00) * 8)
        # Dataset table
        foreach ($Dataset in $this.DatasetTable) {
			[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $Dataset.get_Type());   $writer.Write($bytes_uint16)
			[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $Dataset.get_Offset()); $writer.Write($bytes_uint16)
        }
        # Page table
        foreach ($Page in $this.PageTable) {
			[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $Page.get_Entry()); $writer.Write($bytes_uint32)
			[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $Page.get_Size());  $writer.Write($bytes_uint32)
        }
        # Language table
        foreach ($LangValue in $this.LangTable) {
            if ($null -ne $LangValue) {
				$writer.Write( $LangValue.get_Value() )
            }
        }
        # Done
		$writer.Dispose()
		$stream.Dispose()
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
    [uint16] $Type
    [uint16] $Offset

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
    [uint32] $Entry
    [uint32] $Size

    PageUnit([EXHF]$Exh, [uint32]$Entry, [uint32]$Size) {
        $this.ExhRef = $Exh
        $this.Entry = $Entry
        $this.Size = $Size
    }
}

enum Lang_CodeValue {
    ja  = 1
    en  = 2
    de  = 3
    fr  = 4
    chs = 5
    cht = 6
    ko  = 7
}

class LangUnit {
    [uint16] $Value

    LangUnit([uint16]$LangValue) {
        $this.Value = $LangValue
    }

    static [string] get_LangCodeByValue([int]$LangValue) {
        return [Lang_CodeValue].GetEnumName($LangValue)
    }

    static [int] get_LangValueByCode([string]$LangCode) {
        return [Lang_CodeValue]::$($LangCode)
    }

    [string] get_Code() {
        return [LangUnit]::get_LangCodeByValue($this.Value)
    }
}
