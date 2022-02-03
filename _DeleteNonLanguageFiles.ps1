$files = Get-ChildItem -Recurse
for ($i = 0; $i -lt $files.Count; $i++) {
    if ($files[$i].Name -match "[a-zA-Z0-9]+_[0-9]+.exd" ) {
        $ending = (Select-String -InputObject $files[$i].Name -Pattern "_[0-9]+.exd").Matches.Value
        Remove-Item $files[$i].FullName.Replace($ending, ".exh")
        Remove-Item $files[$i].FullName
    }
}