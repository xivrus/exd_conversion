"QUICK GUIDE"
"This script is supposed to be started from the project's home directory."
"The following structure is expected for this script:"
"  - [home]"
"    -  csv (your current CSVs)"
"       - old (this is where current CSVs will go after the update)"
"    -  new"
"       - csv (CSVs of the new version)`n"
"To perform an update you need to:"
" 1. Extract all EXDs from the new version"
" 2. Put them in 'new' directory inside your project dir"
" 3. Convert them all to CSV using EXDtoCSV script"
" 4. Start this Update script to update CSV to newer version. After the update all CSVs"
"will go into 'old' directory"
" 5. Rename 'bin' and 'source' folders into something else and copy over 'bin' and 'source'"
"from the 'new' folder to your project directory.`n"

$old_csv_path = "$pwd\csv"
$new_csv_path = "$pwd\new\csv"
$old_csv_list = Get-ChildItem "$old_csv_path\*.csv"
$new_csv_list = Get-ChildItem "$new_csv_path\*.csv"

"Found $($old_csv_list.Count) old CSVs and $($new_csv_list.Count) new CSVs at"
"$old_csv_path"
"and"
"$new_csv_path"
if ($old_csv_list.Count -le $new_csv_list.Count) {
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

$old_folder = "$old_csv_path\old"
if (-not $(Test-Path $old_folder)) { $null = New-Item $old_folder -ItemType Directory }
foreach ($new_csv in $new_csv_list) {
    if (Test-Path "$old_csv_path\$($new_csv.Name)" ) {
        $old_csv = Get-Item "$old_csv_path\$($new_csv.Name)"
        $null = Copy-Item $old_csv "$old_folder\$($old_csv.Name)"
        [System.Collections.ArrayList]$old_csv_strings = Get-Content $old_csv -Encoding UTF8
        $new_csv_strings = Get-Content $new_csv.FullName -Encoding UTF8
        $changes_counter = 0
        # Skipping the first row since it's a title
        for ( ($i = 1), ($j = 1); $i -lt $new_csv_strings.Count; $i++, $j++) {
            if ($i -ge $old_csv_strings.Count) {
                $null = $old_csv_strings.Add($new_csv_strings[$i])
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
                $old_csv_strings.RemoveAt($j)
                $null = $old_csv_strings.Insert($j, $new_csv_strings[$i])
                $changes_counter++
            }
        }
        if ($changes_counter) {
            Set-Content -Value $old_csv_strings -Encoding UTF8 -Path $old_csv.FullName
            "$($old_csv.Name) - Done. $changes_counter lines changed."
        } else {
            "$($old_csv.Name) - No changes, left as is."
        }
        
        $new_csv_strings = $null
        $old_csv_strings = $null
    } else {
        $null = Copy-Item $new_csv "$old_csv_path\$($new_csv.Name)"
        "$($new_csv.Name) - New file, copied as is."
    }
}

"Done. Old files were copied into $old_folder."
"Use any diff program with new and old files to check the differences"
"and adjust the translations accordingly."
pause