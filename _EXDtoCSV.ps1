using module .\lib\EXHF.psm1
using module .\lib\EXDF.psm1

$INCLUDE_LIST = @(
    '.\lib\_Settings.ps1',
    '.\lib\Engine.ps1'
)
foreach ($file in $INCLUDE_LIST) {
    try {
        . $file
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        "$file was not found!"
        $error_var = $true
    }
}
if ($error_var) {
    "Put Engine.ps1 and _Settings.ps1 in the 'lib' folder"
    "and restart the script."
    Pause
    break
}

if ($args.Count -eq 0) {
    $host.UI.RawUI.WindowTitle = "EXD -> CSV"
}

New-Variable -Name "UNIX_NL_BYTE" -Value ([byte]0x0A) -Option Constant -ErrorAction SilentlyContinue
New-Variable -Name "VAR_START_BYTE" -Value ([byte]0x02) -Option Constant -ErrorAction SilentlyContinue

:script while ($true) {
    . $INCLUDE_LIST[0]  # Import settings on every iteration so that the user could change them on the fly
    if ($VERBOSE_OUTPUT) {
        $VerbosePreference = "Continue"
    } else {
        $VerbosePreference = "SilentlyContinue"
    }
    $PROJECT_DIR = "$PWD\$CURRENT_DIR"
    $COLUMN_SEPARATOR_BYTE = [System.Text.Encoding]::UTF8.GetBytes($COLUMN_SEPARATOR)

    if (-not $(Test-Path $PROJECT_DIR)) {
        "Do you want`n  $PWD`nto be your project translation folder?"
        $_answer = $(Read-Host "If so, '$PROJECT_DIR\exd_source' and '$PROJECT_DIR\exh_source' folders will be created. (Y/n)").ToLower()
        if ($_answer -eq 'n') {
            "Then move the script to the folder that contains '$PROJECT_DIR' folder."
            pause
            break
        }
        $null = New-Item "$PROJECT_DIR\exd_source" -ItemType Directory -Force
        "Project folders are created. Now put original EXHs and EXDs in 'exd_source' folder.`n"
    }

    $EXH_SOURCE_DIR = "$PROJECT_DIR\exh_source"
    $EXD_SOURCE_DIR = "$PROJECT_DIR\exd_source"
    $EXH_MOD_DIR    = "$PROJECT_DIR\exh_mod"
    $EXD_MOD_DIR    = "$PROJECT_DIR\exd_mod"
    $CSV_DIR        = "$PROJECT_DIR\csv"

    if ($args.Count -gt 0) {
        $input_files = @()
        $GLOBAL_SETTINGS = $true
        $GLOBAL_OVERWRITE = $true
        $GLOBAL_COPY_SOURCE_TO_TRANSLATION = $true

        for ([int] $i = 0; $i -lt $args.Count; $i++) {
            if (Test-Path $args[$i]) {
                $input_files += Get-ChildItem $args[$i]
            }
            if ($args[$i].ToLower() -eq '-currentdir' -and $args[($i+1)] -and (Test-Path $args[($i+1)])) {
                $CURRENT_DIR = $args[($i+1)]

                $PROJECT_DIR = "$PWD\$CURRENT_DIR"

                $EXH_SOURCE_DIR = "$PROJECT_DIR\exh_source"
                $EXD_SOURCE_DIR = "$PROJECT_DIR\exd_source"
                $EXH_MOD_DIR    = "$PROJECT_DIR\exh_mod"
                $EXD_MOD_DIR    = "$PROJECT_DIR\exd_mod"
                $CSV_DIR        = "$PROJECT_DIR\csv"

                $i++
            }
        }

        if ($input_files.Count -eq 0) {
            break script
        }
    } else {
        "Current project folder is $PROJECT_DIR"
        "Expected folders:"
        "Source EXH files (required *):  $EXH_SOURCE_DIR"
        "Source EXD files (EN required): $EXD_SOURCE_DIR"
        "Modded EXH files:               $EXH_MOD_DIR"
        "Modded EXD files:               $EXD_MOD_DIR"
        "Output CSV folder:              $CSV_DIR"
        "* EXH files can be left in 'exd_source' but they will be moved to 'exh_source'."
        "Drag and drop EXH, EXD, or CSV file and press Enter,"
        "or enter 'exh' to get all EXH files in current folder and subfolders,"
        "or enter 'csv' to get all CSV files in current folder and subfolders."
        $input_answer = Read-Host ' '
        $input_answer = $input_answer -replace '^.*?(?=[\w\\.])' -replace '(?<=\w)\W*$'

        switch ( $input_answer.ToLower() ) {
            'exh' {
                $input_files = Get-ChildItem "$PROJECT_DIR\*.exh" -Recurse | Sort-Object
                "$($input_files.Count) EXHs found."
                break
            }
            'csv' {
                $input_files = Get-ChildItem "$PROJECT_DIR\csv\*.csv" -Recurse | Sort-Object
                "$($input_files.Count) CSVs found."
                break
            }
            { Test-Path $_ } {
                $input_files = Get-ChildItem $input_answer
                break
            }
            '' {
                continue script
            }
            default {
                Write-Host "Input file wasn't found at $input_answer.`n" -ForegroundColor DarkRed
                continue script
            }
        }

        $GLOBAL_SETTINGS = $false
        $GLOBAL_OVERWRITE = $false
        $GLOBAL_COPY_SOURCE_TO_TRANSLATION = $true
		$GLOBAL_STRING_INDEXES_CHOICE = $false
    
        $_answer = Read-Host "Do you want to make choices for all file? (Y/n)"
        if ( $_answer.ToLower() -ne 'n' ) {
            $GLOBAL_SETTINGS = $true
    
            "Do you want to overwrite existing CSVs?"
            Write-Warning "You will lose current translations in overwritten files!"
            $_answer = Read-Host '(y/N) '
            if ( $_answer.ToLower() -eq 'y' ) {
                $GLOBAL_OVERWRITE = $true
            }
    
            "Do you want to copy source to translation?"
            $_answer = Read-Host "Choosing 'n' will leave 'Translation' field empty (Y/n)"
            if ( $_answer.ToLower() -eq 'n' ) {
                $GLOBAL_COPY_SOURCE_TO_TRANSLATION = $false
            }

			if ( $GLOBAL_COPY_SOURCE_TO_TRANSLATION ) {
				$_answer = Read-Host "Do you want to add '<index>_' at the start of 'Translation' fields? (y/N)"
				if ( $_answer.ToLower() -eq 'y' ) {
					$GLOBAL_STRING_INDEXES_CHOICE = $true
				}
			}
        }
    }

    $total_start_time = Get-Date
    $error_log = [System.Collections.Generic.List[string]]::new()

    if (New-Item ".\logs" -ItemType Directory -ErrorAction SilentlyContinue) {
        Write-Verbose "Created folder .\logs"
    }
    $log = ".\logs\EXDtoCSV_std_{0:yyyy-MM-ddTHH-mm-ss}.log" -f $total_start_time

    $file_num = 0
    $file_total = $input_files.Count
    foreach ($input_file in $input_files) {
        $component_start_time = Get-Date
        $file_num++
        
        try {
            switch ($input_file.Extension) {
                '.exh' { $base_name = $input_file.BaseName; break }
                '.csv' { $base_name = $input_file.BaseName; break }
                '.exd' { $base_name = $input_file.BaseName -replace '_\d+_[A-z]+$' }
                default { throw }
            }
        }
        catch {
            Write-Host "$($input_file.FullName) has unexpected extension: $($input_file.Extension). Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
            $error_log += $input_file.FullName
            continue
        }
        if (!$base_name) {
            Write-Host "Base name of $($input_file.FullName) turned out empty. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
            $error_log += $input_file.FullName
            continue
        }
        
        $sub_path = $input_file.FullName -replace '.*\\(?:csv|exd_mod|exh_mod|exd_source|exh_source)\\' -replace "(?:\\|)$($base_name).*"
        $csv_path = "$CSV_DIR\$sub_path\$base_name.csv"

        # Questions time
        if ( -not $GLOBAL_SETTINGS ) {
            if ( Test-Path -Path $csv_path ) {
                 else {
                    "$($base_name): CSV already exists - overwrite it?"
                    Write-Warning "You will lose current translation in this file!"
                    $_answer = Read-Host '(y/N) '
                    if ( $_answer.ToLower() -ne 'y' ) {
                        continue
                    }
                    "$($base_name): Confirmed CSV overwrite."
                }
            }

            $COPY_SOURCE_TO_TRANSLATION = $true
            "$($base_name): Do you want to copy source to translation?"
            $_answer = Read-Host "$($base_name): Choosing 'n' will leave 'Translation' field empty (Y/n)"
            if ( $_answer.ToLower() -eq 'n' ) {
                $COPY_SOURCE_TO_TRANSLATION = $false
            }

			$STRING_INDEXES_CHOICE = $false
			if ( $COPY_SOURCE_TO_TRANSLATION ) {
				$_answer = Read-Host "$($base_name): Do you want to add '<index>_' at the start of 'Translation' field? (y/N)"
				if ( $_answer.ToLower() -eq 'y' ) {
					$STRING_INDEXES_CHOICE = $true
				}
			}
        }
        
        if (Test-Path -Path $csv_path) {
            if ( $GLOBAL_OVERWRITE ) {
                "$($base_name): CSV already exists - overwriting by global user choice."
            } else {
                continue
            }
        }

        # If EXH is in 'exd_source', move it to 'exh_source'
        if (Test-Path "$EXD_SOURCE_DIR\$sub_path\$($base_name).exh") {
            $null = New-Item "$EXH_SOURCE_DIR\$sub_path" -ItemType Directory -Force
            Move-Item "$EXD_SOURCE_DIR\$sub_path\$($base_name).exh" "$EXH_SOURCE_DIR\$sub_path\$($base_name).exh" -Force
            Write-Verbose "$($base_name): EXH file was found in 'exd_source' - moved it to 'exh' folder." *>&1 | Tee-Object $log -Append
        }
        $exh_path = "$EXH_SOURCE_DIR\$sub_path\$($base_name).exh"
        if (-not $(Test-Path -Path $exh_path)) {
            Write-Host "$($base_name): EXH file at $exh_path wasn't found. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
            $error_log += $base_name
            continue
        }
        Write-Verbose "$($base_name): EXH file found at $exh_path." *>&1 | Tee-Object $log -Append

        # Keep trying to read the file until either user says to stop,
        # or until there was an error when trying to create EXH object
        do {
            try {
                $exh = [EXHF]::new($exh_path)
                break
            }
            catch [System.IO.IOException] {
                Write-Host "$($base_name): Error while trying to read EXH file at`n  $exh_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
            }
            catch {
                $_ *>&1 | Tee-Object $log -Append
                $error_log += $base_name
                $_answer = 'skip'
            }
        } while ($_answer -ne 'skip')
        if ($_answer -eq 'skip') { continue }
        if ($exh.GetStringDatasetOffsets().Count -eq 0) {
            Write-Verbose "$($base_name): There are no strings, skipping.`n" *>&1 | Tee-Object $log -Append
            $error_log += "$base_name - No strings"
            continue
        }

        $csv = [System.Collections.Generic.List[PSCustomObject]]::new()

        $exd_files = Get-ChildItem -Path "$EXD_SOURCE_DIR\$sub_path\$($base_name)_*_en.exd"
        try {
            $percent = 0
            $1_percent = $exh.get_NumberOfEntries() / 100
            $progress = 0

            if ($exd_files.Count -ne $exh.GetNumberOfPages()) {
                Write-Warning "$($base_name): EN source EXDs were found but incorrect number of pages - ($($exd_files.Count) instead of $($exh.GetNumberOfPages()))" `
                    -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                $error_log += $base_name
                Write-Host "This is a critical issue since EN is considered as the main source and thus required. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                throw [Microsoft.PowerShell.Commands.WriteErrorException]::New()
            }

            $exd_files = $exd_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }
            
            foreach ($page in (0..$($exh.GetNumberOfPages() - 1))) {
                # TODO: Wrong place, move it under strings section
                $file_start_time = Get-Date
                # Keep trying to read the file until either user says to stop,
                # or until there was an error when trying to create EXD object
                do {
                    try {
                        $exd = [EXDF]::new(
                            $exh.GetPage($page),
                            $exh.GetLang('en'),
                            $exd_files[$page]
                        )
                        break
                    }
                    catch [System.IO.IOException] {
                        Write-Host "$($base_name): Error while trying to read EXD file at`n  $($exd_files[$page])" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                        "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                        $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                    }
                    catch {
                        $error_log += $base_name
                        throw $_
                    }
                } while ($_answer -ne 'skip')
                if ($_answer -eq 'skip') { throw [Microsoft.PowerShell.Commands.WriteErrorException]::new() }

                if (($exd.DataRowTable.GetEnumerator().Count) -lt 1) {
                    "$($base_name): EN EXD is empty." *>&1 | Tee-Object $log -Append
                    $error_log += "$base_name - Empty EXD"
                    break
                }

                foreach ($row in $exd.DataRowTable.GetEnumerator()) {
                    [System.Collections.Generic.List[byte]]$string_bytes = $row.Value.GetStringBytesFiltered()
                    $string_bytes.RemoveAt($string_bytes.Count - 1)  # Remove the last 0x00 byte

                    if ($string_bytes.Contains($VAR_START_BYTE) -or $string_bytes.Contains($UNIX_NL_BYTE)) {
                        $string_bytes = Convert-VariablesToTags $string_bytes
                    }

                    $_col_sep_counter = $exh.GetStringDatasetOffsets().Count - 1
                    while ($_col_sep_counter) {
                        $_col_sep_index = $string_bytes.IndexOf( [byte]0x00 )
                        $string_bytes.RemoveAt($_col_sep_index)
                        $string_bytes.InsertRange($_col_sep_index, $COLUMN_SEPARATOR_BYTE)
                        $_col_sep_counter--
                    }

					$exd_index_hex = ''
					if ( $GLOBAL_STRING_INDEXES_CHOICE -or $STRING_INDEXES_CHOICE ) {
                        $exd_index_hex = "{0:X}_" -f $row.Key
                    }

                    $result = [System.Text.Encoding]::UTF8.GetString($string_bytes)

					$translation = ''
					if ( $GLOBAL_COPY_SOURCE_TO_TRANSLATION -or $COPY_SOURCE_TO_TRANSLATION ) {
						$translation = $exd_index_hex + $result
					}

                    $csv.Add( [PSCustomObject]@{
                        Index = "0x{0:X8}" -f $row.Key
                        Translation = $translation
                        Source = $result
                    } )

                    $progress++
                    # +1 to negate this awesome float magic:
                    # > 27340 -gt 27340
                    # False
                    # > 27340 -gt 273.4 * 100
                    # True
                    if ( $progress -gt $1_percent * $percent + 1 ) {
                        $percent++
                        Write-Progress -Activity "[$file_num/$file_total] Converting '$($base_name)'" -Status "$percent% Complete:" -PercentComplete $percent
                    }
                }
                
                $file_diff_time = $(Get-Date) - $file_start_time
                Write-Verbose ("$($exd_files[$page].Name): Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}" -f $file_diff_time) *>&1 | Tee-Object $log -Append
            }
            if ($csv.Count -gt 0) {
                if (New-Item "$CSV_DIR\$sub_path" -ItemType Directory -ErrorAction SilentlyContinue) {
                    Write-Verbose "Created folder: $CSV_DIR\$sub_path\$base_name" *>&1 | Tee-Object $log -Append
                }
                $csv | Export-Csv -Path $csv_path -NoTypeInformation -Encoding UTF8
                Remove-BomFromFile -Path $csv_path
                "$($base_name): $csv_path exported." *>&1 | Tee-Object $log -Append
            }
            Write-Progress -Activity "[$file_num/$file_total] Converting '$($base_name)'" -Completed
        }
        catch [Microsoft.PowerShell.Commands.WriteErrorException] {
            continue
        }
        catch {
            $_ *>&1 | Tee-Object $log -Append
            $error_log += $base_name
            continue
        }
        $component_diff_time = $(Get-Date) - $component_start_time
        Write-Host ("[$file_num/$file_total] $($base_name): Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}`n" -f $component_diff_time) -ForegroundColor Green *>&1 | Tee-Object $log -Append
    }
    $total_diff_time = $(Get-Date) - $total_start_time
    Write-Host ("Finished in {0:hh}:{0:mm}:{0:ss}.{0:fff}`n" -f $total_diff_time) -ForegroundColor Green *>&1 | Tee-Object $log -Append

    if ($error_log) {
        "Encountered the following errors:" *>&1 | Tee-Object $log -Append
        $error_log *>&1 | Tee-Object $log -Append
        '' *>&1 | Tee-Object $log -Append
    }
    # Compress the log file
    Compress-Archive -Path $log -DestinationPath "$log.zip" -CompressionLevel Optimal
    Remove-Item $log

    if ($args.Count -gt 0) {
        break script
    }
}
