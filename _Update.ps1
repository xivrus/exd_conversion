$INCLUDE_LIST = @(
    '.\lib\_Settings.ps1',
    '.\lib\Engine.ps1'
)
$DEPENDENCIES_LIST = @(
    '.\_EXDtoCSV.ps1'
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
foreach ($file in $DEPENDENCIES_LIST) {
    if (-not $(Test-Path $file)) {
        Write-Error "$file was not found!" -Category ObjectNotFound
        $error_var = $true
    }
}
if ($error_var) {
    "Make sure that Engine.ps1 and _Settings.ps1 are 'lib' folder"
    "and that _EXDtoCSV.ps1 is in the same folder as this script."
    "Then restart the script."
    Pause
    break
}

function Compare-Files {
    param (
        # First file
        [string] $File1,
        # Second file
        [string] $File2
    )

    if ( -not ( $(Test-Path $File1) -and $(Test-Path $File2) ) ) {
        return $false
    }

    $hash1 = $(Get-FileHash $File1).hash
    $hash2 = $(Get-FileHash $File2).hash
    return ($hash1 -eq $hash2)
}

function Update-Csv {
    ################################################################
    #.Synopsis
    # Perform an update of the given current CSV file to the
    # given new CSV file. This function edits current CSV and
    # outputs a list of changes in an ArrayList. Keep in mind
    # that we always expect new (source) CSV to exist so this
    # function expects a FileInfo object of the new CSV, not
    # a path!
    #.Parameter CurrentCsv
    # Path to the current CSV.
    #.Parameter NewCsv
    # FileInfo object of the new CSV. Do not confuse with path -
    # you get FileInfo object from Get-ChildItem command.
    ################################################################
    [CmdletBinding()] Param (
        [Parameter(Mandatory=$true)] [String] $CurrentCsvPath,
        [Parameter(Mandatory=$true)] [System.IO.FileInfo] $NewCsv
    )

    try {
        $changelog = [System.Collections.ArrayList]::new()
        $file_name = "\$sub_path\$base_name.csv"
    
        if (Test-Path $CurrentCsvPath) {
            $CurrentCsv = Get-ChildItem -Path $CurrentCsvPath
        
            # Shortcut: If the files are the same then return
            if ( $(Get-FileHash $CurrentCsv -Algorithm SHA1).Hash -eq $(Get-FileHash $NewCsv -Algorithm SHA1).Hash ) {
                $changelog = @()
                "$file_name - No changes, left as is." | Tee-Object $log -Append | Write-Host
                Return ,$changelog
            }
        
            $curr_csv_rows = [System.Collections.ArrayList]@(Import-Csv -Path $CurrentCsv -Encoding UTF8)
            $new_csv_rows = @(Import-Csv -Path $NewCsv -Encoding UTF8)
        
            # Add index to new target strings for components listed in $UPDATE_ADD_INDEX.
            # That way any changed or new strings will have index on them in the game.
            if ( $NewCsv.BaseName -in $UPDATE_ADD_INDEX ) {
                foreach ($row in $new_csv_rows) {
                    $index_hex = "{0:X}_" -f [uint32]$row.Index
                    if (!$row.Translation.StartsWith($index_hex)) {
                        $row.Translation = $index_hex + $row.Translation
                    }
                }
            }
        
            # Comparison cases:
            # Case 1. Current and new strings exist, current index == new index
            # Case 2. Current and new strings exist, current index > new index
            # Case 3. Current and new strings exist, current index < new index
            # Case 4. Only new string exists
            # Case 5. Only current string exists
            for ($row_count = 0; $row_count -lt $new_csv_rows.Count; $row_count++) {
                # Case 4 
                if ($row_count -ge $curr_csv_rows.Count) {
                    $null = $curr_csv_rows.Add($new_csv_rows[$row_count])
                
                    $null = $changelog.Add( [PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = $new_csv_rows[$row_count].Index
                        'Old Translation' = '[N/A]'
                        'New Translation' = $new_csv_rows[$row_count].Translation
                        'Old Source' = '[N/A]'
                        'New Source' = $new_csv_rows[$row_count].Source
                    } )
                
                    continue
                }
            
                $curr_index = [uint32] $curr_csv_rows[$row_count].Index
                $new_index = [uint32] $new_csv_rows[$row_count].Index
            
                # Case 2
                if ($curr_index -gt $new_index) {
                    $null = $curr_csv_rows.Insert($row_count, $new_csv_rows[$row_count])
                
                    $null = $changelog.Add([PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = $new_csv_rows[$row_count].Index
                        'Old Translation' = '[N/A]'
                        'New Translation' = $new_csv_rows[$row_count].Translation
                        'Old Source' = '[N/A]'
                        'New Source' = $new_csv_rows[$row_count].Source
                    })
                
                    continue
                }
            
                # Case 3
                while ($curr_index -lt $new_index) {
                    $null = $changelog.Add([PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = $curr_csv_rows[$row_count].Index
                        'Old Translation' = $curr_csv_rows[$row_count].Translation
                        'New Translation' = '[Removed]'
                        'Old Source' = $curr_csv_rows[$row_count].Source
                        'New Source' = '[Removed]'
                    })
                
                    $curr_csv_rows.RemoveAt($row_count)
                    if ($row_count -ge $curr_csv_rows.Count) { break }
                    $curr_index = [uint32]$curr_csv_rows[$row_count].Index
                }
            
                # Case 1
                if ($curr_csv_rows[$row_count].Source -ne $new_csv_rows[$row_count].Source) {
                    $null = $changelog.Add([PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = $new_csv_rows[$row_count].Index
                        'Old Translation' = $curr_csv_rows[$row_count].Translation
                        'New Translation' = $new_csv_rows[$row_count].Translation
                        'Old Source' = $curr_csv_rows[$row_count].Source
                        'New Source' = $new_csv_rows[$row_count].Source
                    })
                
                    $curr_csv_rows[$row_count] = $new_csv_rows[$row_count]
                }
            }
            # Case 5
            while ($curr_csv_rows.Count -gt $new_csv_rows.Count) {
                $null = $changelog.Add([PSCustomObject]@{
                    'File Name' = $base_name
                    'Index' = '[N/A]'
                    'Old Translation' = $curr_csv_rows[$row_count].Translation
                    'New Translation' = '[Removed]'
                    'Old Source' = $curr_csv_rows[$row_count].Source
                    'New Source' = '[Removed]'
                })
            
                $curr_csv_rows.RemoveAt($curr_csv_rows.Count-1)
            }
        
            if ($changelog) {
                $curr_csv_rows | Export-Csv -Path $CurrentCsv -NoTypeInformation -Encoding UTF8
				Remove-BomFromFile -Path $CurrentCsv
                "$file_name - Done. $($changelog.Count) lines changed." | Tee-Object $log -Append | Write-Host
            } else {
                $changelog = @()
                "$file_name - No changes, left as is." | Tee-Object $log -Append | Write-Host
            }
            # The weird comma is a workaround for PowerShell because
            # for some reason 'return' behaves differently, and if you
            # ask it to return an empty array, it will return $null instead.
            Return ,$changelog
        }
    
        $null = New-Item "$current_csv_dir_path\$sub_path" -ItemType Directory -ErrorAction Ignore
        $null = Copy-Item $NewCsv "$current_csv_dir_path\$sub_path\$($NewCsv.Name)"
    
        $curr_csv_rows = @(Import-Csv -Path $CurrentCsv -Encoding UTF8)
        $curr_csv_rows | Export-Csv $CurrentCsv -NoTypeInformation -Encoding UTF8
        Remove-BomFromFile -Path $CurrentCsv
    
        $null = $changelog.Add([PSCustomObject]@{
            'File Name' = $base_name
            'Index' = '[N/A]'
            'Old Translation' = '[N/A]'
            'New Translation' = '[New file]'
            'Old Source' = '[N/A]'
            'New Source' = '[New file]'
        })
    
        "$file_name - New file, copied as is." | Tee-Object $log -Append | Write-Host
        Return ,$changelog
    }
    catch {
        $_ | Tee-Object $log -Append | Write-Host
        Return ,@()
    }
}


Add-Type -AssemblyName System.Web

if ($VERBOSE_OUTPUT) {
    $VerbosePreference = "Continue"
} else {
    $VerbosePreference = "SilentlyContinue"
}


$PROJECT_PATH = $PWD
# $CURRENT_DIR name is set in _Settings.ps1
$OLD_DIR = 'old'
$NEW_DIR = 'new'

if (-not $(Test-Path "$PROJECT_PATH\$CURRENT_DIR\exd_source")) {
    "There's no 'exd_source' in 'current' folder, aborting."
}
if (-not $(Test-Path "$PROJECT_PATH\$CURRENT_DIR\exh_source")) {
    "There's no 'exh_source' in 'current' folder, aborting."
}

$new_exh_list = Get-ChildItem "$PROJECT_PATH\$NEW_DIR\*.exh" -Recurse
"Found {0} EXH files in 'new' folder." -f $new_exh_list.Count
$_answer = Read-Host "Initiate update? (Y/n)"
if ($_answer.ToLower() -eq 'n') { break }

$total_start_time = Get-Date
if (New-Item ".\logs" -ItemType Directory -ErrorAction SilentlyContinue) {
    Write-Verbose "Created folder .\logs"
}
$log = ".\logs\Update_std_{0:yyyy-MM-ddTHH-mm-ss}.log" -f $total_start_time

"Copying current CSV, source EXHs and EXDs to 'old\x.xx' folder..."
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\csv"        "$PROJECT_PATH\$OLD_DIR\x.xx\csv"        -Recurse -Force
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\exh_source" "$PROJECT_PATH\$OLD_DIR\x.xx\exh_source" -Recurse -Force
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\exd_source" "$PROJECT_PATH\$OLD_DIR\x.xx\exd_source" -Recurse -Force
"Done."

$changelog_table = [System.Collections.ArrayList]::new()

foreach ($new_exh_file in $new_exh_list) {
    $sub_path = $new_exh_file.FullName.Replace("$PROJECT_PATH\$NEW_DIR\", '') `
        -replace 'ex[dh]_source\\' -replace "(?:\\|)$($new_exh_file.Name)$"
    $base_name = $new_exh_file.BaseName

    $current_csv_dir_path = "$PROJECT_PATH\$CURRENT_DIR\csv\$sub_path"
    $current_exd_dir_path = "$PROJECT_PATH\$CURRENT_DIR\exd_source\$sub_path"
    $current_exh_dir_path = "$PROJECT_PATH\$CURRENT_DIR\exh_source\$sub_path"
    $new_csv_dir_path = "$PROJECT_PATH\$NEW_DIR\csv\$sub_path"
    $new_exd_dir_path = "$PROJECT_PATH\$NEW_DIR\exd_source\$sub_path"
    $new_exh_dir_path = "$PROJECT_PATH\$NEW_DIR\exh_source\$sub_path"

    # Move .exh file to new\exh_source if it's in new\exd_source
    if ($new_exh_file.FullName -cmatch [regex]::Escape($new_exd_dir_path)) {
        $new_exh_path = "$new_exh_dir_path\$base_name.exh"

        if (New-Item $(Split-Path $new_exh_path) -ItemType Directory -Force) {
            Write-Verbose "$(Split-Path $new_exh_path) was created." *>&1 | Tee-Object $log -Append
        }
        Move-Item -Path $new_exh_file -Destination $new_exh_path -Force
        $new_exh_file = Get-ChildItem $new_exh_path

        Write-Verbose ("{0}.exh was moved to 'exh_source'" -f $base_name) *>&1 | Tee-Object $log -Append
    }

    $conversion_flag = $false

    $new_exd_list = Get-ChildItem "$new_exd_dir_path\$($base_name)_*_en.exd"
    $current_exh_path = "$current_exh_dir_path\$base_name.exh"

    # Comparison 1. Compare EXH
    if (Compare-Files $new_exh_file $current_exh_path) {
        "{0} - No changes" -f $new_exh_file.Name *>&1 | Tee-Object $log -Append
    } else {
        $current_exh_file = Get-ChildItem $current_exh_path
        Copy-Item -Path $new_exh_file -Destination $current_exh_file -Force

        foreach ($new_exd_file in $new_exd_list) {
            $current_exd_file = Get-ChildItem "$current_exd_dir_path\$($new_exd_file.Name)"
            Copy-Item -Path $new_exd_file -Destination $current_exd_file -Force
        }

        $conversion_flag = $true
        "{0} - EXH changed" -f $new_exh_file.Name *>&1 | Tee-Object $log -Append
    }

    # Comparison 2. Compare EXD
    if ( -not $conversion_flag ) {
        foreach ($new_exd_file in $new_exd_list) {
            $current_exd_file = Get-ChildItem "$current_exd_dir_path\$($new_exd_file.Name)"

            if (Compare-Files $new_exd_file $current_exd_file) {
                "{0} - No changes" -f $new_exd_file.Name *>&1 | Tee-Object $log -Append
            } else {
                Copy-Item -Path $new_exd_file -Destination $current_exd_file -Force
                $conversion_flag = $true
                "{0} - EXD changed" -f $new_exd_file.Name *>&1 | Tee-Object $log -Append
                break
            }
        }
    }

    # Convert new EXDs and compare CSVs
    if ( $conversion_flag ) {
        .\_EXDtoCSV.ps1 $new_exh_file.FullName -CurrentDir 'new' *>&1 | Tee-Object $log -Append

        $new_csv = Get-ChildItem "$new_csv_dir_path\$base_name.csv"
        $current_csv_path = "$current_csv_dir_path\$base_name.csv"

        $changelog_table.InsertRange(
            $changelog_table.Count,
            $(Update-Csv -CurrentCsvPath $current_csv_path -NewCsv $new_csv)
        )
    }
}

if ($changelog_table.Count) {
    New-Item -Path "$PROJECT_PATH\changelogs" -ItemType Directory -Force -ErrorAction Ignore
    $changelog_table | Export-Csv "$PROJECT_PATH\changelogs\x.xx-x.xx Changes.csv" -NoTypeInformation -Encoding UTF8
}

$time_diff = $($(Get-Date) - $total_start_time)
Write-Host ("Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}`n" -f $time_diff) -ForegroundColor Green *>&1 | Tee-Object $log -Append
Pause
