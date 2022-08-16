$EXCLUDE_EXTENSIONS = @('.exh','.ps1')

$files = Get-ChildItem -Recurse -File

foreach ($file in $files) {
    if ($file.Extension -notin $EXCLUDE_EXTENSIONS -and $file.Name -notmatch '_en\.exd$') {
        Remove-Item $file.FullName
        "Deleted $($file.FullName)"
    }
}
pause
