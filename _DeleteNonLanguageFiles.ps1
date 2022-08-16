$EXCLUDE_EXTENSIONS = @('.exh','.ps1')
$EXCLUDE_FILES = @('item.exh')

$files = Get-ChildItem -Recurse -File

foreach ($file in $files) {
    if ($file.Extension -notin $EXCLUDE_EXTENSIONS -and
      $file.Name -notmatch '_[A-z]{2}\.exd$'-and
      $file.Name -notin $EXCLUDE_FILES) {
        $ending = (Select-String -InputObject $file.Name -Pattern '_\d+\.exd').Matches.Value
        if ($ending) {
            $exh_path = $file.FullName.Replace($ending, '.exh')
            if (Test-Path $exh_path) { Remove-Item $exh_path; "Deleted $exh_path" }
        }
        Remove-Item $file.FullName
        "Deleted $($file.FullName)"
    }
}
pause
