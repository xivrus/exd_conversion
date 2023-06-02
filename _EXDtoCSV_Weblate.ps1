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

if (-not $(Test-Path -Path .\config.cfg)) {
	Copy-Item -Path .\config_sample.cfg -Destination .\config.cfg -ErrorAction Stop
}

$UNIX_NL_BYTE   = [byte] 0x0A
$VAR_START_BYTE = [byte] 0x02

:script while ($true) {
	# Import settings on every iteration so that the user could change them on the fly
    . $INCLUDE_LIST[0]
    $CONFIG = Get-Content -Path .\config.cfg | ConvertFrom-StringData

	if ([int] $CONFIG.Verbose) {
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
    $EXH_MOD_DIR    = "$PROJECT_DIR\exh_mod_"
    $EXD_MOD_DIR    = "$PROJECT_DIR\exd_mod_"
    $CSV_DIR        = "$PROJECT_DIR\csv"

    if ($args.Count -gt 0) {
        $input_files = @()
        for ([int] $i = 0; $i -lt $args.Count; $i++) {
            if (Test-Path $args[$i]) {
                $input_files += Get-ChildItem $args[$i]
            }
            if ($args[$i].ToLower() -eq '-currentdir' -and $args[($i+1)] -and (Test-Path $args[($i+1)])) {
                $CURRENT_DIR = $args[($i+1)]

                $PROJECT_DIR = "$PWD\$CURRENT_DIR"

                $EXH_SOURCE_DIR = "$PROJECT_DIR\exh_source"
                $EXD_SOURCE_DIR = "$PROJECT_DIR\exd_source"
                $EXH_MOD_DIR    = "$PROJECT_DIR\exh_mod_"
                $EXD_MOD_DIR    = "$PROJECT_DIR\exd_mod_"
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
        "Modded EXH files:               $EXH_MOD_DIR<language_code>"
        "Modded EXD files:               $EXD_MOD_DIR<language_code>"
        "Output CSV folder:              $CSV_DIR"
        "Default language code:          $DEFAULT_LANGUAGE_CODE (customizable in .\lib\_Settings.ps1)"
        "* EXH files can be left in 'exd_source' but they will be moved to 'exh_source'."
        "Drag and drop EXH, EXD, or CSV file and press Enter,"
        "or enter 'exh' to get all EXH files in current folder and subfolders,"
        "or enter 'csv' to get all $($DEFAULT_LANGUAGE_CODE.ToUpper()) CSV files in current folder and subfolders."
        $input_answer = Read-Host ' '
        # Clean the answer
        $input_answer = $input_answer -replace '^.*?(?=[\w\\.])','' -replace '(?<=\w)\W*$',''
        if ( $input_answer.ToLower() -in ('exh', 'csv') ) {
            switch ($input_answer.ToLower()) {
                'exh' {
                    $input_files = Get-ChildItem "$PROJECT_DIR\*.exh" -Recurse | Sort-Object
                    "$($input_files.Count) EXHs found."
                }
                'csv' {
                    $input_files = Get-ChildItem "$PROJECT_DIR\csv\*\$DEFAULT_LANGUAGE_CODE.csv" -Recurse | Sort-Object
                    "$($input_files.Count) $($DEFAULT_LANGUAGE_CODE.ToUpper()) CSVs found."
                }
            }
            Write-Warning "Source CSVs will not be overwritten if found. Delete them if you want to recreate.`n"
        } elseif (Test-Path $input_answer) {
            $input_files = Get-ChildItem $input_answer
        } else {
            Write-Host "Input file wasn't found at $input_answer.`n" -ForegroundColor DarkRed
            continue
        }
    }

    $total_start_time = Get-Date
    $error_log = [System.Collections.Generic.List[string]]::new()

    if (New-Item ".\logs" -ItemType Directory -ErrorAction SilentlyContinue) {
        Write-Verbose "Created folder .\logs"
    }
    $log = ".\logs\EXDtoCSV_{0}_{1:yyyy-MM-ddTHH-mm-ss}.log" -f $lang_code, $total_start_time

    $file_num = 0
    $file_total = $input_files.Count
    foreach ($input_file in $input_files) {
        $component_start_time = Get-Date
        $file_num++
        
        try {
            switch ($input_file.Extension) {
                '.exh' { $base_name = $input_file.BaseName; break }
                '.csv' { $base_name = $input_file.Directory.Name; break }
                '.exd' { $base_name = $input_file.BaseName -replace '_\d+_[A-z]+$','' }
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
        
        $sub_path = $input_file.FullName -replace '.*\\(?:csv|exd_mod_\w+|exh_mod_\w+|exd_source|exh_source)\\','' -replace "$($base_name).*",''

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

        # $langs_csv Structure:
        #                             @{ source = ...; target = ...;  . . .  }
        # @{en = PSCustomObject[] } > @{ source = ...; target = ...;  . . .  }
        #                             @{ source = ...; target = ...;  . . .  }
        #                             @{ source = ...; target = ...;  . . .  }
        # @{de = PSCustomObject[] } > @{ source = ...; target = ...;  . . .  }
        #                             @{ source = ...; target = ...;  . . .  }
        #   . . .
        # CSV is assembled from $langs_csv['en'].Values
        $langs_csv = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[PSCustomObject]]]::new()
        $langs_csv.Add(
            'en',
            [System.Collections.Generic.List[PSCustomObject]]::new()
        )  # EN must go first
        # This variable keeps EN source strings as hashtable: @{ Index = Source_string }
        $en_source = [System.Collections.Generic.Dictionary[int,string]]::new()
        $exd_file_list = Get-ChildItem -Path "$EXD_SOURCE_DIR\$sub_path\$($base_name)_*.exd"
        [System.Collections.Generic.List[string]] $lang_ignore_list = @( 'en' )
        foreach ($exd_file in $exd_file_list) {
            $lang_code = $exd_file.BaseName -replace '^.*_',''
            if ($lang_code -notin $lang_ignore_list -and $lang_code -notin $langs_csv.Keys) {
                if (Test-Path "$CSV_DIR\$sub_path\$base_name\$lang_code.csv") {
                    Write-Verbose "$($base_name): CSV for $($lang_code.ToUpper()) was found, skipping." *>&1 | Tee-Object $log -Append
                    $lang_ignore_list.Add($lang_code)
                    continue
                }
                $langs_csv.Add(
                    $lang_code.ToLower(),
                    [System.Collections.Generic.List[PSCustomObject]]::new()
                )
            }
        }
        if ($langs_csv.Count -eq 1) {
            Write-Verbose "$($base_name): No conversion needed, skipping.`n" *>&1 | Tee-Object $log -Append
            $error_log += "$base_name - No conversion needed"
            continue
        }
        try {
            $percent = 0
            $1_percent = $exh.get_NumberOfEntries() / (100 / $langs_csv.Count)
            $progress = 0
            foreach ($lang_csv in $langs_csv.GetEnumerator()) {
                $lang_code = $lang_csv.Key
                $csv_path = "$CSV_DIR\$sub_path\$base_name\$lang_code.csv"
                $exd_files = $exd_file_list | Where-Object { $_.BaseName -like "*_$($lang_code)" }
                if ($exd_files.Count -ne $exh.GetNumberOfPages()) {
                    Write-Warning "$($base_name): $($lang_code.ToUpper()) source EXDs were found but incorrect number of pages - ($($exd_en_files.Count) instead of $($exh.GetNumberOfPages()))" `
                        -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    $error_log += $base_name
                    if ($lang_code -eq 'en') {
                        Write-Host "This is a critical issue since EN is considered as the main source and thus required. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                        throw [Microsoft.PowerShell.Commands.WriteErrorException]::New()
                    }
                }
                $exd_files = $exd_files | Sort-Object { [int]($_.BaseName -split '_')[-2] }

                $fuzzy = $lang_code -notin $OFFICIAL_LANGUAGES
                foreach ($page in (0..$($exh.GetNumberOfPages() - 1))) {
                    # TODO: Wrong place, move it under strings section
                    $file_start_time = Get-Date
                    # Keep trying to read the file until either user says to stop,
                    # or until there was an error when trying to create EXD object
                    do {
                        try {
                            $exd = [EXDF]::new(
                                $exh.GetPage($page),
                                $exh.GetLang($exh_lang),
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
                        "$($base_name): $($lang_code.ToUpper()) EXD is empty." *>&1 | Tee-Object $log -Append
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
                        $result = [System.Text.Encoding]::UTF8.GetString($string_bytes)

                        if ($lang_code -eq 'en') {
                            $en_source.Add(
                                $row.Key,
                                $result
                            )
                        }
                        $lang_csv.Value.Add(
                            [PSCustomObject]@{
                                location = ''
                                source = $( if ($lang_code -eq 'en') { $result } else { $en_source.$($row.Key) } )
                                target = $result
                                id = ''
                                fuzzy = $fuzzy
                                context = "0x{0:X8}" -f $row.Key
                                translator_comments = ''
                                developer_comments = ''
                            }
                        )

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
                if ($lang_code -eq 'en' -and $(Test-Path "$CSV_DIR\$sub_path\$base_name\$lang_code.csv")) {
                    continue
                }
                if ($lang_csv.Value.Count -gt 0) {
                    if (New-Item "$CSV_DIR\$sub_path\$base_name" -ItemType Directory -ErrorAction SilentlyContinue) {
                        Write-Verbose "Created folder: $CSV_DIR\$sub_path\$base_name" *>&1 | Tee-Object $log -Append
                    }
                    $lang_csv.Value | Export-Csv -Path $csv_path -NoTypeInformation -Encoding UTF8
                    Remove-BomFromFile -Path $csv_path
                    "$($base_name): $csv_path exported." *>&1 | Tee-Object $log -Append
                }
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
    Compress-Archive -Path $log -DestinationPath "$log.zip" -CompressionLevel Optimal -Force
    Remove-Item $log

    if ($args.Count -gt 0) {
        break script
    }
}
