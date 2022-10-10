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
    $host.UI.RawUI.WindowTitle = "CSV -> EXD - Weblate"
}

New-Variable -Name "UNIX_NL_BYTE" -Value ([byte]0x0A) -Option Constant -ErrorAction SilentlyContinue
New-Variable -Name "VAR_START_BYTE" -Value ([byte]0x02) -Option Constant -ErrorAction SilentlyContinue

while ($true) {
    . $INCLUDE_LIST[0]  # Import settings on every iteration so that the user could change them on the fly
    $GLOBAL_CUSTOMIZE = $false
    if ($VERBOSE_OUTPUT) {
        $VerbosePreference = "Continue"
    } else {
        $VerbosePreference = "SilentlyContinue"
    }

    if ($QUEST_EXCLUDE_LIST[0] -and $QUEST_INCLUDE_LIST[0]) {
        Write-Host "Error: Lists QUEST_EXCLUDE_LIST and QUEST_INCLUDE_LIST are both non-empty.`nOne of them must be empty." -ForegroundColor DarkRed
        "Edit those lists correctly and press Enter to reload settings."
        pause
        continue
    }
    if ($QUEST_EXCLUDE_LIST[0]) {
        Write-Verbose "Quest files - working with exclude list."
    }
    if ($QUEST_INCLUDE_LIST[0]) {
        Write-Verbose "Quest files - working with include list."
    }

    $PROJECT_DIR = "$PWD\$CURRENT_DIR"
    if (!$(Test-Path $PROJECT_DIR) ) {
        "$PWD is not a project translation folder. ('$CURRENT_DIR' folder wasn't found)"
        "Start with EXDtoCSV script in this folder to generate project structure"
        "and convert some files to work with."
        Pause
        break   
    }

    $EXH_SOURCE_DIR = "$PROJECT_DIR\exh_source"
    $EXD_SOURCE_DIR = "$PROJECT_DIR\exd_source"
    $EXH_MOD_DIR    = "$PROJECT_DIR\exh_mod_"
    $EXD_MOD_DIR    = "$PROJECT_DIR\exd_mod_"
    $CSV_DIR        = "$PROJECT_DIR\csv"
    
    if ($args.Count -gt 0) {
        $input_files = @()
        foreach ($arg in $args) {
            if (Test-Path $arg) {
                $input_files += Get-ChildItem $arg
            }
        }
        if ($input_files.Count -eq 0) {
            break script
        }
    } else {
        "Current project folder is $PROJECT_DIR"
        "Expected folders:"
        "Source EXH files (required):    $EXH_SOURCE_DIR"
        "Source EXD files (EN required): $EXD_SOURCE_DIR"
        "Modded EXH files:               $EXH_MOD_DIR<lang_code>"
        "Modded EXD files:               $EXD_MOD_DIR<lang_code>"
        "CSV files (required):           $CSV_DIR"
        "Default language code:          $DEFAULT_LANGUAGE_CODE (customizable in .\lib\_Settings.ps1)"
        "Drag and drop EXH, EXD, or CSV file and press Enter,"
        "or enter 'exh' to get all EXH files in 'exh_source' and 'exh_mod_<lang>' folders,"
        "or enter language code to get all CSV files of this language in current folder and subfolders."
        # Clean the answer of possible trash symbols at the start and the end
        $input_answer = $(Read-Host ' ') -replace '^.*?(?=[\w\\.])','' -replace '(?<=\w)\W*$',''
        if ($input_answer -eq '') {
            "`n"
            continue
        }
        if (Test-Path $input_answer) {
            $input_files = Get-ChildItem $input_answer
        } else {
            $input_answer = $input_answer.ToLower()
            switch ($input_answer) {
                'exh' {
                    # The sctipt will work with all found languages.
                    # Also if an appropriate modded EXH is found then it'll be used instead.
                    $input_files = Get-ChildItem "$EXH_SOURCE_DIR\*.exh" -Recurse
                    "$($input_files.Count) EXHs found."
                }
                default {
                    $lang_code = $input_answer
                    $input_files = Get-ChildItem "$CSV_DIR\*\$lang_code.csv" -Recurse
                    "$($input_files.Count) $($lang_code.ToUpper()) CSVs found."
                }
            }
            "Do you want to make choices for all files?"
            $_answer = $(Read-Host "If not then you'll have to choose manually for each file. (Y/n)").ToLower()
            switch ($_answer) {
                'n' { $GLOBAL_CUSTOMIZE = $false }
                default {
                    $GLOBAL_CUSTOMIZE = $true
                    $_answer = $(Read-Host "Do you want to overwrite all existing EXD files? (Y/n)").ToLower()
                    switch ($_answer) {
                        'n' { $SILENTLY_OVERWRITE = $false }
                        default { $SILENTLY_OVERWRITE = $true }
                    }
                    "Do you want to add string index ('<index>_') at the start of translation fields?"
                    $_answer = $(Read-Host "Add if doesn't exist / Remove if exists / do Nothing (a/r/N)").ToLower()
                    switch ($_answer) {
                        'a' { $STRING_INDEXES_CHOICE = 1 }
                        'r' { $STRING_INDEXES_CHOICE = 2 }
                        default { $STRING_INDEXES_CHOICE = 0 }
                    }
                    $_answer = $(Read-Host "Do you want to also add file number at the start of translation field? (y/N)").ToLower()
                    switch ($_answer) {
                        'y' { $ADD_FILE_NUMBER = $true }
                        default { $ADD_FILE_NUMBER = $false }
                    }
                }
            }
        }
    }
    $total_start_time = Get-Date
    $syntax_error_log = [System.Collections.Generic.List[string]]::new()

    if (New-Item ".\exports" -ItemType Directory -ErrorAction SilentlyContinue) {
        Write-Verbose "Created folder .\exports"
    }
    $TT_export = ".\exports\TexTools_{0}_{1:yyyy-MM-ddTHH-mm-ss}.txt" -f $lang_code, $total_start_time
    if (New-Item ".\logs" -ItemType Directory -ErrorAction SilentlyContinue) {
        Write-Verbose "Created folder .\logs"
    }
    $log = ".\logs\CSVtoEXD_{0}_{1:yyyy-MM-ddTHH-mm-ss}.log" -f $lang_code, $total_start_time

    $file_num = 0
    $file_total = $input_files.Count
    try {
        foreach ($input_file in $input_files) {
            $file_start_time = Get-Date
            $file_num++

            switch ($input_file.Extension) {
            '.exh'  {
                $base_name = $input_file.BaseName
                if ($input_file.FullName -like "$EXH_MOD_DIR*") {
                    $lang_code = $input_file.FullName.Replace($EXH_MOD_DIR,'') -replace '\\.*$',''
                } else {
                    $lang_code = $DEFAULT_LANGUAGE_CODE
                }
                break
            }
            '.csv'  {
                $base_name = $input_file.Directory.Name
                $lang_code = $input_file.BaseName
                break
            }
            '.exd' {
                $base_name = $input_file.BaseName -replace '_\d+_[A-z]+$',''
                $lang_code = switch ($input_file.FullName) {
                    { $_ -like "$EXD_MOD_DIR*" } {  # Get language from 'exd_mod_<lang>' folder name
                        $input_file.FullName.Replace($EXD_MOD_DIR,'') -replace '\\.*$',''
                    }
                    { $_ -like "$EXD_SOURCE_DIR*" } {  # Get language from file name if it's source
                        $input_file.BaseName -replace '^.*_',''
                    }
                    default {  # Shouldn't happen, or in case current file was manually renamed
                        $DEFAULT_LANGUAGE_CODE
                    }
                }
            }
            }
            if (!$base_name) {
                Write-Host "Base name of $($input_file.FullName) turned out empty. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                continue
            }
            $sub_path = $input_file.FullName -replace '^.*\\(?:csv|exd_mod_\w+|exh_mod_\w+|exd_source|exh_source)\\','' -replace "\\$($base_name).*$",''
            
            # Include/exclude logic for quest files
            if ($sub_path -cmatch '^(?:exd\\|)(?:cut_scene|opening|quest).*$') {
                if ($QUEST_EXCLUDE_LIST[0]) {
                    if ($base_name -in $QUEST_EXCLUDE_LIST) {
                        Write-Warning "$($base_name): Found in exclude list. Skipping." *>&1 | Tee-Object $log -Append
                        "" *>&1 | Tee-Object $log -Append
                        continue
                    } else {
                        Write-Verbose "$($base_name): Not found in exclude list." *>&1 | Tee-Object $log -Append
                    }
                }
                if ($QUEST_INCLUDE_LIST[0]) {
                    if ($base_name -in $QUEST_INCLUDE_LIST) {
                        Write-Verbose "$($base_name): Found in include list." *>&1 | Tee-Object $log -Append
                    } else {
                        Write-Warning "$($base_name): Not found in include list. Skipping." *>&1 | Tee-Object $log -Append
                        "" *>&1 | Tee-Object $log -Append
                        continue
                    }
                }
            }

	        # Collect data from EXH
            if (Test-Path "$EXH_MOD_DIR$lang_code\$sub_path\$base_name.exh") {
                $exh_path = "$EXH_MOD_DIR$lang_code\$sub_path\$base_name.exh"
                Write-Verbose "$($base_name): Modded $($lang_code.ToUpper()) EXH file found at $exh_path." *>&1 | Tee-Object $log -Append
            } else {
                $exh_path = "$EXH_SOURCE_DIR\$sub_path\$base_name.exh"
                if (-not $(Test-Path $exh_path)) {
                    Write-Host "$($base_name): EXH file at $exh_path wasn't found. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    continue
                }
                Write-Verbose "$($base_name): Original EXH file found at $exh_path." *>&1 | Tee-Object $log -Append
            }
            Write-Verbose "$($base_name): Reading EXH at $exh_path" *>&1 | Tee-Object $log -Append
            do {
                try {
                    $exh = [EXHF]::new($exh_path)
                    break
                }
                catch [System.IO.IOException] {
                    Write-Host "$($base_name): Error while trying to read $exh_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                    $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                }
                catch {
                    $_ *>&1 | Tee-Object $log -Append
                    $_answer = 'skip'
                }
            } while ($_answer -ne 'skip')
            if ($_answer -eq 'skip') { continue }

            $csv_mod_file = Get-ChildItem -Path "$CSV_DIR\$sub_path\$base_name\$lang_code.csv"
            if (-not $csv_mod_file) {
                Write-Host "$($base_name): $lang_code.csv file wasn't found under '$base_name' folder. Skipping.`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                continue
            }
            Write-Verbose "$($base_name): $csv_mod_file was found." *>&1 | Tee-Object $log -Append
            $csv_path = $csv_mod_file.FullName

            Write-Verbose "$($base_name): Reading input CSV at $csv_path" *>&1 | Tee-Object $log -Append
            do {
                try {
                    $csv = @(Import-Csv -Path $csv_path -Encoding UTF8)
                    break
                }
                catch [System.IO.IOException] {
                    Write-Host "$($base_name): Error while trying to read CSV file at`n  $csv_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                    $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                }
                catch {
                    $_ *>&1 | Tee-Object $log -Append
                    $_answer = 'skip'
                }
            } while ($_answer -ne 'skip')
            if ($_answer -eq 'skip') { continue }
            if ($csv.Count -lt 1) {
                Write-Host "$($base_name): $($lang_code.ToUpper()) input CSV turned out empty. Skipping...`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                continue
            }

            # Ask questions
            if (!$GLOBAL_CUSTOMIZE) {
                "$($base_name): Choose what to do with '<index>_' at the start of translation fields:"
                $_answer = $(Read-Host "Add if doesn't exist / Remove if exists / do Nothing (a/r/N)").ToLower()
                switch ($_answer) {
                    "a" { $STRING_INDEXES_CHOICE = 1 }
                    "r" { $STRING_INDEXES_CHOICE = 2 }
                    default { $STRING_INDEXES_CHOICE = 0 }
                }
            }
            if (!$SILENTLY_OVERWRITE -and ($exh.GetNumberOfPages() -gt 1)) {
                $_answer = $(Read-Host "$($base_name): Several EXDs will be generated from this CSV. Overwrite them all? (Y/n)").ToLower()
                if ($_answer -eq 'n') {
                    $silently_overwrite_multipage = $false
                } else {
                    $silently_overwrite_multipage = $true
                    Write-Warning "If any of generated EXDs is the same as the one that already exists`nit will not be overwritten anyway."
                }
            }

            if ($base_name -in $QUEST_ADD_INDEX_LIST) {
                $quest_add_index_flag = $true
                Write-Verbose "$($base_name): File name found in `$QUEST_ADD_INDEX_LIST, will add decimal indexes." *>&1 | Tee-Object $log -Append
            }


            $csv_cache_path = "$EXD_MOD_DIR$lang_code\csv_cache\$sub_path\$($base_name)_cache.csv"
            # Sublanguage subroutine:
            # 1. Determine parent language
            # 2. Check if parent has cache and read it if exists. If not - skip
            # 3. Check if there's a cache for current language. If not - copy parent's one
            # 4. Fill empty translation strings in input CSV according to the rules below:
            #   a. If sublang is not empty, don't do anything
            #   b. If sublang is empty, take parent lang
            #   c. If parent lang is empty too, take source lang
            # 5. Check the comparsion flag
            if ($SUBLANGUAGES[$lang_code]) {
                # Step 1
                $parent_lang_code = $SUBLANGUAGES[$lang_code]
                Write-Verbose "$($base_name): Parent's language - $($parent_lang_code.ToUpper())" *>&1 | Tee-Object $log -Append

                # Step 2
                $csv_parent_cache_path = $csv_cache_path.Replace("$EXD_MOD_DIR$lang_code", "$EXD_MOD_DIR$parent_lang_code")
                if (-not (Test-Path $csv_parent_cache_path)) {
                    Write-Host "$($base_name): Parent's cache was not found - it is required for a sublanguage. Skipping...`n" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    continue
                }
                Write-Verbose "$($base_name): Reading parent's cache at $csv_parent_cache_path" *>&1 | Tee-Object $log -Append
                do {
                    try {
                        $csv_parent_cache = @(Import-Csv -Path $csv_parent_cache_path -Encoding UTF8)
                        break
                    }
                    catch [System.IO.IOException] {
                        Write-Host "$($base_name): Error while trying to read parent cache $($parent_lang_code.ToUpper()) file at`n  $csv_parent_cache_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                        "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                        $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                    }
                    catch {
                        $_ *>&1 | Tee-Object $log -Append
                        $_answer = 'skip'
                    }
                } while ($_answer -ne 'skip')
                if ($_answer -eq 'skip') { continue }

                # Step 3
                if (-not (Test-Path $csv_cache_path)) {
                    if (New-Item $(Split-Path $csv_cache_path -Parent) -ItemType Directory -ErrorAction SilentlyContinue) {
                        Write-Verbose "$($base_name): Created folder $(Split-Path $csv_cache_path -Parent)" *>&1 | Tee-Object $log -Append
                    }    
                    Copy-Item -Path $csv_parent_cache_path -Destination $csv_cache_path
                    Write-Verbose "$($base_name): Parent's $($parent_lang_code.ToUpper()) cache is cached to $csv_cache_path" *>&1 | Tee-Object $log -Append
                }
                
                # Step 4
                foreach ($i in (0..$($csv.Count - 1))) {
                    if ($csv[$i].target -eq '') {
                        if ($csv_parent_cache[$i].target -eq '') {
                            $csv[$i].target = $csv[$i].source
                        } else {
                            $csv[$i].target = $csv_parent_cache[$i].target
                        }
                    }
                }
                # Step 5
                $compare_with_cache = $true
            } else
            # General language subroutine:
            # 1. Fill all empty translation strings with source
            # 2. If cache doesn't exist, use source CSV (en.csv) as cache
            {
                $parent_lang_code = $null
                $csv_parent_cache_path = $null
                $csv_parent_cache = $null
                # Step 1
                foreach ($i in (0..$($csv.Count - 1))) {
                    if ($csv[$i].target -eq '') {
                        $csv[$i].target = $csv[$i].source
                    }
                }
                # Step 2
                if (-not (Test-Path $csv_cache_path)) {
                    Write-Verbose "$($base_name): Cache was not found." *>&1 | Tee-Object $log -Append
                    if (New-Item $(Split-Path $csv_cache_path -Parent) -ItemType Directory -ErrorAction SilentlyContinue) {
                        Write-Verbose "$($base_name): Created folder $(Split-Path $csv_cache_path -Parent)" *>&1 | Tee-Object $log -Append
                    }    
                    Copy-Item -Path $csv_path.Replace("$lang_code.csv", "en.csv") -Destination $csv_cache_path
                    Write-Verbose "$($base_name): Source EN CSV is cached to $csv_cache_path" *>&1 | Tee-Object $log -Append
                }

                $compare_with_cache = -not $STRING_INDEXES_CHOICE
                if ($STRING_INDEXES_CHOICE) {
                    Write-Verbose "$($base_name): Requested to change strings - ignoring current cache if it exists." *>&1 | Tee-Object $log -Append
                }
            }

            if ( $quest_add_index_flag ) {
                $compare_with_cache = $false
				Remove-Item -Path $csv_cache_path -ErrorAction Ignore
            }

            if ($compare_with_cache) {
                Write-Verbose "$($base_name): Reading cache at $csv_cache_path" *>&1 | Tee-Object $log -Append
                do {
                    try {
                        $csv_cache = @(Import-Csv -Path $csv_cache_path -Encoding UTF8)
                        break
                    }
                    catch [System.IO.IOException] {
                        Write-Host "$($base_name): Error while trying to read cache at`n  $csv_cache_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                        "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                        $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                    }
                    catch {
                        $_ *>&1 | Tee-Object $log -Append
                        $_answer = 'skip'
                    }
                } while ($_answer -ne 'skip')
                if ($_answer -eq 'skip') { continue }
            }


            # Conversion start
            $percent = 0
            # This variable keeps an amount of string columns to add in EXH.
            # It's set on the first row. After that, the script will check
            # the rest of the rows against this value since this amount must be
            # consistent across _all_ rows. Otherwise the whole component will fail.
            $exh_add_string_columns = $null
            $csv_start_row = 0
            $csv_current_row = 0
            # Should we cache input CSV? Check 'yes' if anything was changed
            $cache_input = $false
            foreach ($page in $exh.PageTable) {
                $page_start_time = Get-Date

                # Set up paths
                $exd_file_name =   "$($base_name)_$($page.get_Entry())_en.exd"
                $exd_source_path = "$EXD_SOURCE_DIR\$sub_path\$exd_file_name"
                $exd_mod_path =    "$EXD_MOD_DIR$lang_code\$sub_path\$exd_file_name"
                $exd_game_path =   "$sub_path\$exd_file_name" -replace '\\','/'
                if ( -not $exd_game_path.StartsWith('exd') ) { $exd_game_path = 'exd' + $exd_game_path }

                Write-Verbose "$($base_name): Reading EXD file at $exd_source_path" *>&1 | Tee-Object $log -Append
                do {
                    try {
                        $exd = [EXDF]::new($page, $exh.GetLang('en'), $exd_source_path)
                        break
                    }
                    catch [System.IO.IOException] {
                        Write-Host "$($base_name): Error while trying to read source EXD file at`n  $exd_source_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                        "If it exists, then it's probably locked by some program." *>&1 | Tee-Object $log -Append
                        $_answer = $(Read-Host "Press Enter to try again or enter 'skip' to skip").ToLower()
                    }
                    catch {
                        $_ *>&1 | Tee-Object $log -Append
                        $_answer = 'skip'
                    }
                } while ($_answer -ne 'skip')

                # Compare relevant input CSV rows with cached CSV.
                # If they're all the same skip to the next page.
                if ($compare_with_cache) {
                    $is_page_different = $false
                    Write-Verbose "$($base_name): Checking against cache CSV if input CSV changed." *>&1 | Tee-Object $log -Append
                    $csv_end_row = if ($exh.GetNumberOfPages() -eq 1) { $exd.DataRowTable.Count - 1 } else { $csv_start_row + $page.get_Size() - 1 }

                    # For sublanguage: If there's more than 1 page and EXD file for current page doesn't exist,
                    # compare with parent cache, not with own cache. This is for situations when e.g. parent language
                    # was changed but sublanguage was left with source strings on purpose. The script will then
                    # create an EXD that is identical to the source one. This will happen only once per page.
                    if ($SUBLANGUAGES[$lang_code] -and $exh.GetNumberOfPages() -gt 1 -and -not (Test-Path $exd_mod_path)) {
                        foreach ($i in ($csv_start_row..$csv_end_row)) {
                            if ($csv[$i].target -ne $csv_parent_cache[$i].target) {
                                "$($base_name): Page $($page.get_Entry()) changed in $($SUBLANGUAGES[$lang_code].ToUpper())." *>&1 | Tee-Object $log -Append
                                $is_page_different = $true
                                $cache_input = $true
                                break
                            }
                        }
                    } else {
                        foreach ($i in ($csv_start_row..$csv_end_row)) {
                            if ($csv[$i].target -ne $csv_cache[$i].target) {
                                "$($base_name): Page $($page.get_Entry()) changed." *>&1 | Tee-Object $log -Append
                                $is_page_different = $true
                                $cache_input = $true
                                break
                            }
                        }
                    }

                    $csv_current_row = $csv_start_row
                    $csv_start_row += $page.get_Size()
                    if (-not $is_page_different) {
                        "$($base_name): Page $($page.get_Entry()) didn't change." *>&1 | Tee-Object $log -Append
                        continue
                    }
                }

                if (New-Item "$EXD_MOD_DIR$lang_code\$sub_path" -ItemType Directory -ErrorAction SilentlyContinue) {
                    Write-Verbose "$($base_name): Created folder $EXD_MOD_DIR$lang_code\$sub_path" *>&1 | Tee-Object $log -Append
                }
                if (!$SILENTLY_OVERWRITE -and !$silently_overwrite_multipage -and $(Test-Path $exd_mod_path)) {
                    $_answer = $(Read-Host "$($base_name): $exd_mod_path already exists. Overwrite? (Y/n)").ToLower()
                    if ($_answer -eq 'n') {
                        continue
                    }
                }

                if ($ADD_FILE_NUMBER) {
                    $file_index_hex = "{0:X}_" -f $file_num
                } else {
                    $file_index_hex = ''
                }

                $1_percent = $csv.Count / 100
                foreach ($row in $exd.DataRowTable.GetEnumerator()) {
                    switch ($STRING_INDEXES_CHOICE) {
                        0 { # Do nothing
                            $exd_index_hex = ''
                            break
                        }
                        1 { # Add index if doesn't exist
                            $exd_index_hex = "{0:X}_" -f [int32]$csv[$csv_current_row].context
                            if ( $csv[$csv_current_row].target.StartsWith($exd_index_hex) ) { $exd_index_hex = '' }
                            break
                        }
                        2 { # Remove index if exists
                            $exd_index_hex = "{0:X}_" -f [int32]$csv[$csv_current_row].context
                            if ( $csv[$csv_current_row].target.StartsWith($exd_index_hex) ) {
                                $csv[$csv_current_row].target = $csv[$csv_current_row].target.Substring($exd_index_hex.Length)
                            }
                            $exd_index_hex = ''
                        }
                    }

                    if ($csv[$csv_current_row].target.Length -gt 0) {
                        try {
                            if ( $quest_add_index_flag ) {
								$csv_row_number = "{0}_" -f ($csv_current_row + 1)
								if ( $csv[$csv_current_row].target.StartsWith('TEXT_') ) {
                                	# Один из переводчиков попросил это. Также по его просьбе индекс именно в десятичном формате, чтобы
                                	# совпадал с номером строки в Weblate. Когда EXDtoCSV перестанет включать в CSV-файлы пустые строки,
                                	# с этим надо будет что-то делать.
                                	$string = $csv[$csv_current_row].target -replace '<tab>',("<tab>{0}{1}_" -f $file_index_hex, $csv_row_number)
								} else {
                                	$string = $file_index_hex + $csv_row_number + $csv[$csv_current_row].target
								}
                            } else {
                                $string = $file_index_hex + $exd_index_hex + $csv[$csv_current_row].target
                            }
                            $result_bytes = Convert-TagsToVariables $string
                        }
                        catch {
                            Write-Host "$($base_name): Error at line $($csv[$csv_current_row].context):" -ForegroundColor Red *>&1 | Tee-Object $log -Append
                            $_ *>&1 | Tee-Object $log -Append
                            $error_var = $true
                        }    
                    } else {
                        $result_bytes = [System.Text.Encoding]::UTF8.GetBytes($file_index_hex + $exd_index_hex) + [byte[]]@(0x00)
                    }

                    $amount_of_strings = $result_bytes.Where({ $_ -eq 0x00 }).Count
                    if ($amount_of_strings -ne $exh.GetStringDatasetOffsets().Count) {
                        if ($csv_current_row -eq 0) {
                            $exh_add_string_columns = $amount_of_strings - $exh.GetStringDatasetOffsets().Count
                            if ($exh_add_string_columns -lt 0) {
                                Write-Host ("$($base_name): New amount of string columns is less that original - {0} against {1}" -f `
                                    $exh_add_string_columns, $exh.GetStringDatasetOffsets().Count) -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                                $syntax_error_var = $true
                                break
                            }
                            Write-Verbose "$($base_name): Recognized $exh_add_string_columns new string column(s)." *>&1 | Tee-Object $log -Append
                            try {
                                foreach ($i in (1..$exh_add_string_columns)) {
                                    $exh.AddDataset('string', $exd)
                                    Write-Verbose "$($base_name): String column added." *>&1 | Tee-Object $log -Append
                                }
                            }
                            catch {
                                Write-Host "$($base_name): Failed to add a new column" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                                $_ *>&1 | Tee-Object $log -Append
                                $error_var = $true
                                break
                            }
                            $exh_mod_path = "$EXH_MOD_DIR$lang_code\$sub_path\$base_name.exh" *>&1 | Tee-Object $log -Append
                            try {
                                $exh.Export($exh_mod_path)
                            }
                            catch {
                                Write-Host "$($base_name): Failed to export modded EXH to $exh_mod_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                                $_ *>&1 | Tee-Object $log -Append
                                $error_var = $true
                                break
                            }
                        } else {
                            Write-Host $("$($base_name): The amount of new string columns is inconsistent at {0} - {1} instead of {2}" -f `
                                $csv[$csv_current_row].context, $amount_of_strings, $exh.GetStringDatasetOffsets().Count) -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                            $syntax_error_var = $true
                            $syntax_error_log.Add( $("  {0} - {1}" -f $base_name, $csv[$csv_current_row].context) )
                            $cache_input = $false
                        }
                    }

                    if (-not $error_var -and -not $syntax_error_var) {
                        $row.Value.SetStringBytes($result_bytes)
                    }

                    # +1 to negate this awesome float magic:
                    # > 27340 -gt 27340
                    # False
                    # > 27340 -gt 273.4 * 100
                    # True
                    if ( $csv_current_row -gt $1_percent * $percent + 1 ) {
                        Write-Progress -Activity "[$file_num/$file_total] Converting '$base_name'" -Status "$percent% Complete:" -PercentComplete $percent
                        $percent += 1
                    }
                    $csv_current_row++
                }

                if ($syntax_error_var) {
                    Write-Verbose "$($base_name): There was a syntax error in the page. Moving on to the next page." *>&1 | Tee-Object $log -Append
                    $syntax_error_var = $false
                    continue
                }
                if ($error_var) {
                    "$($base_name): Skipping due to an error.`n" *>&1 | Tee-Object $log -Append
                    $error_var = $false
                    break
                }

                try {
                    $exd.ExportEXD($exd_mod_path)
                }
                catch {
                    Write-Host "$($base_name): Got an error while exporting EXD to $exd_mod_path" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
                    $_ *>&1 | Tee-Object $log -Append
                    continue
                }
                "$($base_name): $exd_mod_path exported." *>&1 | Tee-Object $log -Append
                if ($exh_add_string_columns -gt 0) {
                    $exh_game_path = "$sub_path\$base_name.exh" -replace '\\','/'
                    if ( -not $exh_game_path.StartsWith('exd') ) { $exh_game_path = 'exd' + $exh_game_path }
                    $exh_game_path >> $TT_export
                    $exh_mod_path >> $TT_export
                    '' >> $TT_export
                }
                $exd_game_path >> $TT_export
                $exd_mod_path >> $TT_export
                '' >> $TT_export

                $page_diff_time = $(Get-Date) - $page_start_time
                Write-Verbose ("$($exd_file_name): Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}" -f $page_diff_time) *>&1 | Tee-Object $log -Append
            }

            if ($exh_add_string_columns -gt 0) {
                $exh_mod_path = "$EXH_MOD_DIR$lang_code\$sub_path\$base_name.exh"
                try {
                    $exh.Export($exh_mod_path)
                }
                catch {
                    Write-Host "$($base_name): Failed to export modded EXH to $exh_mod_path" *>&1 | Tee-Object $log -Append
                    $_ *>&1 | Tee-Object $log -Append
                    continue
                }
            }

            if ( $cache_input ) {
                if (New-Item $(Split-Path $csv_cache_path -Parent) -ItemType Directory -ErrorAction SilentlyContinue) {
                    Write-Verbose "$($base_name): Created folder $(Split-Path $csv_cache_path -Parent)" *>&1 | Tee-Object $log -Append
                }
                $csv | Export-Csv -Path $csv_cache_path -Encoding UTF8 -NoTypeInformation -Force
                Write-Verbose "$($base_name): Input CSV is cached to $csv_cache_path" *>&1 | Tee-Object $log -Append

                $silently_overwrite_multipage = $false
                Write-Progress -Activity "[$file_num/$file_total] Converting '$base_name'" -Status "Completed" -Completed
            }

            $quest_add_index_flag = $false
            $file_time_diff = $(Get-Date) - $file_start_time
            Write-Host ("[$file_num/$file_total] $($base_name): Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}`n" -f $file_time_diff) -ForegroundColor Green *>&1 | Tee-Object $log -Append
        }
    }
    catch {
        $_ *>&1 | Tee-Object $log -Append
    }

    $total_diff_time = $(Get-Date) - $total_start_time
    Write-Host ("Finished in {0:hh}:{0:mm}:{0:ss}.{0:fff}" -f $total_diff_time) -ForegroundColor Green *>&1 | Tee-Object $log -Append
    if ($ADD_FILE_NUMBER) {
        "File indexes:" *>&1 | Tee-Object $log -Append
        for ($_i = 0; $_i -lt $input_files.Count; $_i++){
            "  {0:X} - {1}" -f ($_i+1), ($input_files[$_i].BaseName) *>&1 | Tee-Object $log -Append
        }
    }
    if ($syntax_error_log) {
        Write-Host "There were syntax errors in the following files:" -ForegroundColor DarkRed *>&1 | Tee-Object $log -Append
        $syntax_error_log *>&1 | Tee-Object $log -Append
    }
    if (Test-Path $TT_export) {
        Write-Host "List of modded files is saved to $TT_export`n" -ForegroundColor Green *>&1 | Tee-Object $log -Append
    } else {
        "There were no changes.`n" *>&1 | Tee-Object $log -Append
    }

    # Compress the log file
    Compress-Archive -Path $log -DestinationPath "$log.zip" -CompressionLevel Optimal
    Remove-Item $log 

    ''

    if ($args.Count -gt 0) {
        break script
    }
}
