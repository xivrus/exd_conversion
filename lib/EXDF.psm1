# This file contains EXDF class and its supplementary classes
using module .\EXHF.psm1
using namespace System.Buffers.Binary

class EXDF {
    [EXHF] $EXH
    [string] $Path

    static [uint32] $Signature = 0x45584446 # "EXDF"
    static [uint16] $Version = 0x0002
    [uint16] $Unknown
    $DataRowTable = [System.Collections.Generic.Dictionary[uint32,DataRowUnit]]::new()

    # Passing FileInfo object is also accepted
    EXDF([EXHF] $ExhObject, [string] $Path) {
		$file_name = Split-Path -Path $Path -Leaf
		if ($file_name -notmatch '\.exd$') {
			throw [System.IO.InvalidDataException]::new(
                "File extension is not '.exd'."
            )
		}
		$this.EXH = $ExhObject
		$this.Path = $Path

		$stream = [System.IO.FileStream]::new($this.Path, [System.IO.FileMode]::Open)
		$reader = [System.IO.BinaryReader]::new($stream)

		$sig = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
        if ($sig -ne [EXDF]::Signature) {
            throw [System.IO.InvalidDataException]::new(
                "Incorrect format: File signature is not EXDF."
            )
        }
        $ver = [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )
        if ($ver -ne [EXDF]::Version) {
            Write-Warning "Unexpected EXD version: {0} instead of {1}`n`tFile: $Path" -f $ver, [EXDF]::Version
        }
        $this.Unknown = [BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) )

		$total_entries = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) ) / 8
        if ($total_entries -lt 1) {
			return
		}
		$data_size = $this.EXH.get_SizeOfDatasetChunk()
        foreach ($i in (0..$($total_entries - 1))) {
			$index_pos = 0x20 + $i * 8

			$stream.Seek($index_pos, [System.IO.SeekOrigin]::Begin)
			$index      = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
            $offset_pos = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )

			$stream.Seek($offset_pos, [System.IO.SeekOrigin]::Begin)
            $size = [BinaryPrimitives]::ReadUInt32BigEndian( $reader.ReadBytes(4) )
			$string_size = $size - $data_size
            $this.DataRowTable.Add(
                $index,
                [DataRowUnit]::new(
                    $this.EXH,
                    $size,
					[BinaryPrimitives]::ReadUInt16BigEndian( $reader.ReadBytes(2) ),
                    $reader.ReadBytes( $data_size ),
                    $reader.ReadBytes( $string_size )
                )
            )
        }

		$reader.Dispose()
		$stream.Dispose()
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
		$stream = [System.IO.FileStream]::new($Destination, [System.IO.FileMode]::Create)
		$writer = [System.IO.BinaryWriter]::new($stream)

        foreach ($DataRow in $this.DataRowTable.GetEnumerator()) {
            $writer.Write($DataRow.Value.DataBytes)
        }

		$writer.Dispose()
		$stream.Dispose()
	}

    [void] ExportEXD([string]$Destination) {
		$stream = [System.IO.FileStream]::new($Destination, [System.IO.FileMode]::Create)
		$writer = [System.IO.BinaryWriter]::new($stream)
		$bytes_uint32 = [byte[]](0x00) * 4
		$bytes_uint16 = [byte[]](0x00) * 2

        $offset_table_size = $this.DataRowTable.Count * 8

		# Header except DataSectionSize
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, [EXDF]::Signature);  $writer.Write($bytes_uint32)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, [EXDF]::Version);    $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $this.Unknown);      $writer.Write($bytes_uint16)
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $offset_table_size); $writer.Write($bytes_uint32)
		$writer.Write([byte[]](0x00) * 4)   # 0x0C..0x0F is DataSectionSize, it will be filled later
		$writer.Write([byte[]](0x00) * 16)  # Padding
        # Offset table + Data section
		# * Offset table is fixed size while data section is dynamic
		# * Because of this we'll fill offset table with zeros first
		#   * It doesn't actually write to disk yet, stream buffer is used instead until the file is closed
		$offset_current_pos = $stream.Position
		$writer.Write([byte[]](0x00) * $offset_table_size)
        $data_current_pos = $stream.Position
        foreach ($DataRow in $this.DataRowTable.GetEnumerator()) {
			$stream.Seek($offset_current_pos, [System.IO.SeekOrigin]::Begin)
			[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $DataRow.Key);      $writer.Write($bytes_uint32)
			[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $data_current_pos); $writer.Write($bytes_uint32)
			$offset_current_pos = $stream.Position

			$stream.Seek($data_current_pos, [System.IO.SeekOrigin]::Begin)
			[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $DataRow.Value.SizeOfChunk); $writer.Write($bytes_uint32)
			[BinaryPrimitives]::WriteUInt16BigEndian($bytes_uint16, $DataRow.Value.Unknown);     $writer.Write($bytes_uint16)
			$writer.Write($DataRow.Value.DataBytes)
			$writer.Write($DataRow.Value.StringBytes)
            $data_current_pos = $stream.Position
        }
        # Calculate and fill DataSectionSize
		# * $data_current_pos is now at the end of the file
		# * 32 is header size
        $data_section_size = $data_current_pos - $offset_table_size - 32
		$stream.Seek(0x0C, [System.IO.SeekOrigin]::Begin)
		[BinaryPrimitives]::WriteUInt32BigEndian($bytes_uint32, $data_section_size); $writer.Write($bytes_uint32)
        # Done
		$writer.Dispose()
		$stream.Dispose()
	}
}

class DataRowUnit {
    [EXHF] $EXH
    [uint32] $SizeOfChunk
    [uint16] $Unknown
    [byte[]] $DataBytes
    [byte[]] $StringBytes

    DataRowUnit([EXHF]$EXH, [uint32]$s, [uint16]$u, [byte[]]$d, [byte[]]$str) {
        $this.EXH = $EXH
        $this.SizeOfChunk = $s
        $this.Unknown = $u
        $this.DataBytes = $d
        $this.StringBytes = $str
    }

    [int] GetStringIndex([int]$StrDatasetNum) {
        return [BitConverter]::ToUInt32($this.DataBytes[
            ($this.EXH.GetStringDatasetOffsets()[$StrDatasetNum] + 3)..($this.EXH.GetStringDatasetOffsets()[$StrDatasetNum])
        ], 0)
    }

    [byte[]] GetStringBytesFiltered() {
        if ($this.EXH.GetStringDatasetOffsets().Count -eq 0) { return [byte[]]@() }
        return $this.StringBytes[0..([array]::IndexOf(
                $this.StringBytes,
                [byte]0x00,
                $this.GetStringIndex(-1)
            ))]
    }

    # Align the whole chunk to 0x04 bytes if necessary
    [void] AlignChunk() {
        $chunk_size = $this.DataBytes.Count + $this.StringBytes.Count
        if ($this.SizeOfChunk -ne $chunk_size) {
			# 2 is $this.Unknown byte size
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
        for ($i = 1; $i -lt $this.EXH.GetStringDatasetOffsets().Count; $i++) {
            [System.BitConverter]::GetBytes(
                [array]::IndexOf($StringBytes, [byte]0x00, $this.GetStringIndex($i-1)) + 1
            )[3..0].CopyTo(
                $this.DataBytes,
                $this.EXH.GetStringDatasetOffsets()[$i]
            )
        }
        $this.AlignChunk()
    }
}
