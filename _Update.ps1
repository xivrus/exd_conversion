"QUICK GUIDE"
"This script is supposed to be started from the project's home directory."
"The following structure is expected for this script:"
"├───current *
│   ├───bin
│   ├───csv *
│   ├───exd_mod
│   └───exd_source
├───new *
│   ├───bin
│   ├───csv *
│   ├───exd_mod
│   └───exd_source
└───old **
    └───x.xx **
        ├───bin
        ├───csv
        └───exd_source"
"* These ones are required for this script."
"** These ones will be created.`n"
"To perform an update you need to:"
" 1. Extract all EXDs from the new version wherever you'd like to"
" 2. Clear them off non-language EXHs and EXDs with _DeleteNonLanguageFiles.ps1"
" 3. Put your dumped 'exd' folder into 'new\exd_mod' keeping the original file structure"
" 4. Copy EXDtoCSV script into 'new' and run it to convert all new EXDs to CSV"
" 5. Start this Update script from project root to update current CSVs to a newer version."
"All old CSVs will go into 'old\x.xx\csv' directory."
" 6. Move 'bin' and 'exd_source' folders from 'current' to 'old\x.xx'. Feel free to rename"
"'x.xx' to previously current version of the game."
" 7. Move 'bin' and 'exd_source' folders from 'new' to 'current'"
" 8. Mass-convert all new CSVs to EXDs, or convert only previously modified CSVs to EXDs."
"Either way, you're done.`n"

$CURRENT_DIR = 'current'
$CURRENT_CSV_DIR_PATH = "$PWD\$CURRENT_DIR\csv"
$NEW_CSV_DIR_PATH = "$PWD\new\csv"
$OLD_CSV_DIR_PATH = "$PWD\old\x.xx\csv"
$CHANGELOG_CSV_PATH = "$PWD\x.xx-x.xx Changes.csv"
$SCRIPT_LOG_PATH = "$PWD\x.xx-x.xx Changes.log"
$current_csv_files = Get-ChildItem "$CURRENT_CSV_DIR_PATH\*.csv" -Recurse
$new_csv_files = Get-ChildItem "$NEW_CSV_DIR_PATH\*.csv" -Recurse

"Found $($current_csv_files.Count) current CSVs at"
"  $CURRENT_CSV_DIR_PATH"
"and $($new_csv_files.Count) new CSVs at"
"  $NEW_CSV_DIR_PATH."
if ($current_csv_files.Count -le $new_csv_files.Count) {
    $answer = Read-Host "Do you want to start the update process? (Y/n)"
    switch ($answer) {
        "n" { exit }
        default {}
    }
} else {
    $answer = Read-Host "Their amount DOES NOT match. This may or may not be normal, please double check.`nDo you still want to start the update process? (y/N)"
    switch ($answer) {
        "y" {}
        default { break }
    }
}

$changelog_csv = New-Object System.Collections.ArrayList
if ( !$(Test-Path $OLD_CSV_DIR_PATH) ) { $null = New-Item $OLD_CSV_DIR_PATH -ItemType Directory }

foreach ($new_csv in $new_csv_files) {
    $SUB_PATH = $new_csv.FullName.Replace($NEW_CSV_DIR_PATH, "").Replace($($new_csv.Name), "")
    if (Test-Path "$CURRENT_CSV_DIR_PATH$SUB_PATH$($new_csv.Name)" ) {
        $old_csv = Get-Item "$CURRENT_CSV_DIR_PATH$SUB_PATH$($new_csv.Name)"
        if (!$(Test-Path "$OLD_CSV_DIR_PATH$SUB_PATH")) { $null = New-Item "$OLD_CSV_DIR_PATH$SUB_PATH" -ItemType Directory }
        $null = Copy-Item $old_csv "$OLD_CSV_DIR_PATH$SUB_PATH$($old_csv.Name)" -Recurse -Force
        [System.Collections.ArrayList]$old_csv_rows = Import-Csv $old_csv
        $new_csv_rows = Import-Csv $new_csv.FullName
        $changes_counter = 0
        for ( ($i = 0), ($j = 0); $i -lt $new_csv_rows.Count; $i++, $j++) {
            if ($i -ge $old_csv_rows.Count) {
                $null = $old_csv_rows.Add($new_csv_rows[$i])
                $null = $changelog_csv.Add(
                    [PSCustomObject]@{
                        'File Name' = $new_csv.Name
                        'Old Translation String' = 'N/A'
                        'Old Source String' = 'N/A'
                        'New String' = $new_csv_rows[$i].Source
                    }
                )
                $changes_counter++
                continue
            }

            $old_index = [uint32]$old_csv_rows[$j].Index
            $new_index = [uint32]$new_csv_rows[$i].Index
            if ($old_index -gt $new_index) {
                $null = $old_csv_rows.Insert($j, $new_csv_rows[$i])
                $changes_counter++
                continue
            }
            while ($old_index -lt $new_index) {
                $old_csv_rows.RemoveAt($j)
                $old_index = [uint32]$old_csv_rows[$j].Index
            }

            if ($old_csv_rows[$j].Index -ne $new_csv_rows[$i].Index) {
                "String IDs do not match at $($old_csv.Name), $j and $($new_csv.Name), $i" | Tee-Object -FilePath $SCRIPT_LOG_PATH -Append | Write-Host
                "The script will now exit. Please resolve this issue manually and try again." | Tee-Object -FilePath $SCRIPT_LOG_PATH -Append | Write-Host
                pause
                exit
            }
            if ($old_csv_rows[$j].Source -ne $new_csv_rows[$i].Source) {
                $null = $changelog_csv.Add(
                    [PSCustomObject]@{
                        'File Name' = $new_csv.Name
                        'Old Translation String' = $old_csv_rows[$j].Translation
                        'Old Source String' = $old_csv_rows[$j].Source
                        'New String' = $new_csv_rows[$i].Source
                    }
                )
                $old_csv_rows.RemoveAt($j)
                $null = $old_csv_rows.Insert($j, $new_csv_rows[$i])
                $changes_counter++
            }
        }
        if ($changes_counter) {
            $old_csv_rows | Export-Csv $old_csv.FullName -NoTypeInformation -Encoding UTF8
            "$SUB_PATH$($old_csv.Name) - Done. $changes_counter lines changed." | Tee-Object -FilePath $SCRIPT_LOG_PATH -Append | Write-Host
        } else {
            "$SUB_PATH$($old_csv.Name) - No changes, left as is." | Tee-Object -FilePath $SCRIPT_LOG_PATH -Append | Write-Host
        }
        
        $new_csv_rows = $null
        $old_csv_rows = $null
    } else {
        if (!$(Test-Path "$CURRENT_CSV_DIR_PATH$SUB_PATH")) { $null = New-Item "$CURRENT_CSV_DIR_PATH$SUB_PATH" -ItemType Directory }
        $null = Copy-Item $new_csv "$CURRENT_CSV_DIR_PATH$SUB_PATH$($new_csv.Name)"$null = $changelog_csv.Add(
            [PSCustomObject]@{
                'File Name' = $new_csv.Name
                'Old Translation String' = 'N/A'
                'Old Source String' = 'N/A'
                'New String' = 'New file'
            }
        )
        "$SUB_PATH$($new_csv.Name) - New file, copied as is." | Tee-Object -FilePath $SCRIPT_LOG_PATH -Append | Write-Host
    }
}

$changelog_csv | Export-Csv $CHANGELOG_CSV_PATH -NoTypeInformation -Encoding UTF8
Move-Item "$PWD\$CURRENT_DIR\bin"        "$PWD\old\x.xx"
Move-Item "$PWD\$CURRENT_DIR\exd_source" "$PWD\old\x.xx"
Move-Item "$PWD\new\bin"            "$PWD\$CURRENT_DIR"
Move-Item "$PWD\new\exd_source"     "$PWD\$CURRENT_DIR"

"Done."
"- Old files were copied into $PWD\old\x.xx"
"- Differences were saved into 'x.xx-x.xx Changes.csv'"
"- Script log was saved into 'x.xx-x.xx Changes.log'"
"Please rename all x.xx according to respective old and new versions of the game."
pause