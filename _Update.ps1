"QUICK GUIDE"
"This script is supposed to be started from the project's home directory."
"The following structure is expected for this script:"
"├───current
│   ├───bin
│   ├───csv *
│   ├───exd_mod
│   └───exd_source
├───new
│   ├───bin
│   ├───csv *
│   ├───exd_mod
│   └───exd_source
└───old
    └───x.xx
        ├───bin
        ├───csv
        └───exd_source"
"* These ones are required.`n"
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

$current_csv_path = "$PWD\current\csv"
$new_csv_path = "$PWD\new\csv"
$old_csv_path = "$PWD\old\x.xx\csv"
$current_csv_list = Get-ChildItem "$current_csv_path\*.csv" -Recurse
$new_csv_list = Get-ChildItem "$new_csv_path\*.csv" -Recurse

"Found $($current_csv_list.Count) current CSVs and $($new_csv_list.Count) new CSVs at"
"$current_csv_path"
"and"
"$new_csv_path"
if ($current_csv_list.Count -le $new_csv_list.Count) {
    $answer = Read-Host "respectively. Do you want to start the update process? (Y/n)"
    switch ($answer) {
        "n" { break }
        default {}
    }
} else {
    $answer = Read-Host "respectively. Their amount DOES NOT match. This may or may not be normal, please double check.`nDo you still want to start the update process? (y/N)"
    switch ($answer) {
        "y" {}
        default { break }
    }
}

# If you're going to change the separator, make sure the script file is in UTF-8 BOM
$CSV_SEPARATOR = '┃'

# Preparing a new array which is going to be a CSV file with all changes
$changelog_csv = New-Object System.Collections.ArrayList
$null = $changelog_csv.Add("File Name,Old String,New String")

if (-not $(Test-Path $old_csv_path)) { $null = New-Item $old_csv_path -ItemType Directory }
foreach ($new_csv in $new_csv_list) {
    $SUB_PATH = $new_csv.FullName.Replace($new_csv_path, "").Replace($($new_csv.Name), "")
    if (Test-Path "$current_csv_path$SUB_PATH$($new_csv.Name)" ) {
        $old_csv = Get-Item "$current_csv_path$SUB_PATH$($new_csv.Name)"
        if (!$(Test-Path "$old_csv_path$SUB_PATH")) { $null = New-Item "$old_csv_path$SUB_PATH" -ItemType Directory }
        $null = Copy-Item $old_csv "$old_csv_path$SUB_PATH$($old_csv.Name)" -Recurse -Force
        [System.Collections.ArrayList]$old_csv_strings = Get-Content $old_csv -Encoding UTF8
        $new_csv_strings = Get-Content $new_csv.FullName -Encoding UTF8
        $changes_counter = 0
        # Skipping the first row since it's a title
        for ( ($i = 1), ($j = 1); $i -lt $new_csv_strings.Count; $i++, $j++) {
            if ($i -ge $old_csv_strings.Count) {
                $null = $old_csv_strings.Add($new_csv_strings[$i])
                $null = $changelog_csv.Add("`"$($new_csv.Name)`",`"`",`"$($new_csv_strings[$i])`"")
                $changes_counter++
                continue
            }

            $old_index = [uint32]$old_csv_strings[$j].Substring(0, 10) # '0x00000000'.Length
            $new_index = [uint32]$new_csv_strings[$i].Substring(0, 10)
            if ($old_index -gt $new_index) {
                $null = $old_csv_strings.Insert($j, $new_csv_strings[$i])
                $changes_counter++
                continue
            }
            while ($old_index -lt $new_index) {
                $old_csv_strings.RemoveAt($j)
                $old_index = [uint32]$old_csv_strings[$j].Substring(0, 10)
            }

            $old_source = $old_csv_strings[$j].Substring( $old_csv_strings[$j].LastIndexOf($CSV_SEPARATOR) )
            $new_source = $new_csv_strings[$i].Substring( $new_csv_strings[$i].LastIndexOf($CSV_SEPARATOR) )
            if ($old_csv_strings[$j].Substring(0, 10) -ne $new_csv_strings[$i].Substring(0, 10)) {
                "String IDs do not match at $($old_csv.Name), $j and $($new_csv.Name), $i"
                "The script will exit. Please resolve this issue manually and try again."
                pause
                exit
            }
            if ($old_source -ne $new_source) {
                $null = $changelog_csv.Add("`"$($new_csv.Name)`",`"$($old_csv_strings[$j])`",`"$($new_csv_strings[$i])`"")
                $old_csv_strings.RemoveAt($j)
                $null = $old_csv_strings.Insert($j, $new_csv_strings[$i])
                $changes_counter++
            }
        }
        if ($changes_counter) {
            Set-Content -Value $old_csv_strings -Encoding UTF8 -Path $old_csv.FullName
            "$SUB_PATH$($old_csv.Name) - Done. $changes_counter lines changed."
        } else {
            "$SUB_PATH$($old_csv.Name) - No changes, left as is."
        }
        
        $new_csv_strings = $null
        $old_csv_strings = $null
    } else {
        if (!$(Test-Path "$current_csv_path$SUB_PATH")) { $null = New-Item "$current_csv_path$SUB_PATH" -ItemType Directory }
        $null = Copy-Item $new_csv "$current_csv_path$SUB_PATH$($new_csv.Name)"
        $null = $changelog_csv.Add("`"$($new_csv.Name)`",`"N/A`",`"New file`"")
        "$SUB_PATH$($new_csv.Name) - New file, copied as is."
    }
}

$changelog_csv > .\changelog.csv
Move-Item "$PWD\current\bin"        "$PWD\old\x.xx"
Move-Item "$PWD\current\exd_source" "$PWD\old\x.xx"
Move-Item "$PWD\new\bin"            "$PWD\current"
Move-Item "$PWD\new\exd_source"     "$PWD\current"

"Done."
"- Old files were copied into $old_csv_path."
"- Differences were saved into 'changelog.csv'."
"- It is also recommended to save 'at a glance' diffs from above to a separate text file."
pause