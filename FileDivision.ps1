param(
	[Parameter(Mandatory)]
	[ValidateSet('Divide','Combine')]
	[string]$Operation
)

if ( $PSVersionTable.PSVersion.Major -lt 7 ) {
	"This script was created for PowerShell Core 7.x"
	pause
	break
}

. .\lib\_Settings.ps1

# This script shouldn't exist but I got too lazy to implement
# proper file division which would actually require a little rewrite
# of Dataset portion in _EXDF.ps1.

# $DIVIDE_FILES = @{ item = 'itemname(0,1,3);itemtransient(2)' }
foreach ( $file_original in $DIVIDE_FILES.Keys ) {
	$file_split_args = $DIVIDE_FILES[$file_original] -split ';'
	$file_splits = foreach ( $file_split_arg in $file_split_args ) {
		$file_split_arg -replace '\(.*'
	}
	$file_columns = foreach ( $file_split_arg in $file_split_args ) {
		$file_columns_arg = $file_split_arg -replace '^.*\(' -replace '\)$'
		$_result = $file_columns_arg -split ','
		,@($_result)
	}

	if ( $Operation -eq 'Divide' ) {
		"Operation: Divide"
		$file_original_dir = Get-ChildItem `
			-Path .\current\csv\exd `
			-Filter $file_original `
			-Recurse -Directory
		for ( $i = 0; $i -lt $file_splits.Count; $i++ ) {
			# Now we have:
			#   $file_original   - original file name
			#   $file_splits[$i] - current split file name
			#   $file_columns    - array of column numbers to keep in a split file
			"  $file_original => $($file_splits[$i])"
			"  Columns: $($file_columns[$i] -join ', ')"
			$file_split_dir = $file_original_dir.FullName -replace "$file_original`$", $file_splits[$i]
			try {
				if ( New-Item -Path $file_split_dir -ItemType Directory -ErrorAction Stop ) {
					"  Directory $file_split_dir created."
				}
			}
			catch [System.IO.IOException] {
				"  Directory $file_split_dir already exists."
			}
			catch {
				$_
				continue
			}
			$file_original_csvs = Get-ChildItem -Path $file_original_dir -Filter '*.csv'
			foreach ( $file_original_csv in $file_original_csvs ) {
				$file_split_csv_path = $file_split_dir + '/' + $file_original_csv.Name
				$csv = Import-Csv -Path $file_original_csv -Encoding utf8NoBOM
				foreach ( $row in $csv ) {
					$source_split = $row.source -split $COLUMN_SEPARATOR
					$row.source = $(foreach ( $column in $file_columns[$i] ) {
						$source_split[ [int]$column ]
					}) -join $COLUMN_SEPARATOR

					$target_split = $row.target -split $COLUMN_SEPARATOR
					$row.target = $(foreach ( $column in $file_columns[$i] ) {
						$target_split[ [int]$column ]
					}) -join $COLUMN_SEPARATOR
				}
				$csv | Export-Csv -Path $file_split_csv_path -Encoding utf8NoBOM
				"  $($file_original_csv.Name) done."
			}
		}

		Remove-Item -Path "$file_original_dir\*.csv"
		if ( -not $(Get-ChildItem -Path $file_original_dir) ) {
			Remove-Item -Path $file_original_dir
		}
	}
	if ( $Operation -eq 'Combine' ) {
		"Operation: Combine"
		# I'm ultra lazy to make a proper code for this

		$file_1_dir = Get-Item ".\current\csv\exd\$($file_splits[0])"
		$file_2_dir = Get-Item ".\current\csv\exd\$($file_splits[1])"
		$file_original_dir = ".\current\csv\exd\$file_original"
		if ( -not $(Test-Path $file_original_dir) ) {
			New-Item -Path $file_original_dir -ItemType Directory
		}

		$langs = [System.Collections.Generic.List[string]]::new()
		foreach ( $file in $(Get-ChildItem $file_2_dir -File) ) {
			$langs.Add( $file.BaseName )
		}

		foreach ( $lang in $langs ) {
			$csv_1 = Import-Csv "$file_1_dir\$lang.csv" -Encoding utf8
			$csv_2 = Import-Csv "$file_2_dir\$lang.csv" -Encoding utf8
			if ( $lang -eq 'ru' ) {
				$csv_1 = Import-Csv "$file_1_dir\en.csv" -Encoding utf8
			}
			if ( $lang -eq 'ru_BACKUP' ) {
				continue
			}

			for ( $row_num = 0; $row_num -lt $csv_1.Count; $row_num++ ) {
				$source_1_split = $csv_1[$row_num].source -split $COLUMN_SEPARATOR
				$source_2_split = $csv_2[$row_num].source -split $COLUMN_SEPARATOR
				$source = $(
					$source_1_split[0],
					$source_1_split[1],
					$source_2_split[0],
					$source_1_split[2]
				) -join $COLUMN_SEPARATOR

				$target_1_split = $csv_1[$row_num].target -split $COLUMN_SEPARATOR
				$target_2_split = $csv_2[$row_num].target -split $COLUMN_SEPARATOR
				$target = $(
					$target_1_split[0],
					$target_1_split[1],
					$target_2_split[0],
					$target_1_split[2]
				) -join $COLUMN_SEPARATOR

				$csv_1[$row_num].source = $source
				$csv_1[$row_num].target = $target
			}

			$csv_1 | Export-Csv "$file_original_dir\$lang.csv" -Encoding utf8NoBOM
		}

		Remove-Item $file_1_dir -Recurse
		Remove-Item $file_2_dir -Recurse
	}
}
