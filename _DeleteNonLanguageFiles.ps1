$files = Get-ChildItem -Recurse
for ($i = 0; $i -lt $files.Count; $i++) {
    if ($files[$i].Name -notmatch '_[A-z]{2}\.exd$' ) {
        $ending = (Select-String -InputObject $files[$i].Name -Pattern '_\d+\.exd').Matches.Value
        Remove-Item $files[$i].FullName.Replace($ending, '.exh')
        Remove-Item $files[$i].FullName
    }
}