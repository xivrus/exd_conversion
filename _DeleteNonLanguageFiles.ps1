$files = Get-ChildItem -Recurse
for ($i = 0; $i -lt $files.Count; $i++) {
    if ($files[$i].Extension -notin @('.exh','.ps1') -and $files[$i].Name -notmatch '_[A-z]{2}\.exd$') {
        $ending = (Select-String -InputObject $files[$i].Name -Pattern '_\d+\.exd').Matches.Value
        if ($ending) {
            $exh_path = $files[$i].FullName.Replace($ending, '.exh')
            if (Test-Path $exh_path) { Remove-Item $exh_path; "Deleted $exh_path" }
        }
        Remove-Item $files[$i].FullName
        "Deleted $($files[$i].FullName)"
    }
}
pause
