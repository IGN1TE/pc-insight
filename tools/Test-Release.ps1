# Every suite runs in a fresh process so mocks and native types cannot leak.
param([switch]$Portable)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Get-ChildItem $root -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors | Out-String)}
}
foreach($file in 'MainWindow.xaml','GameOverlay.xaml'){[xml]$null=Get-Content (Join-Path $root $file) -Raw -Encoding UTF8}
$windowsOnly=@('Test-Interface','Test-GpuOverclockUI','Test-ComparisonWorkflow','Test-SessionComparisonUI','Test-NativeSensors','Test-SessionLibraryUI')
$hostPath=(Get-Process -Id $PID).Path
$failures=@();$passed=0;$skipped=0
foreach($suite in (Get-ChildItem (Join-Path $root 'tests') -Filter 'Test-*.ps1' | Sort-Object Name)){
    if($Portable -and $suite.BaseName -in $windowsOnly){Write-Host "SKIP Windows-only: $($suite.Name)";$skipped++;continue}
    Write-Host "RUN $($suite.Name)"
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass')
    if(-not $Portable){$arguments+='-STA'}
    & $hostPath @arguments -File $suite.FullName
    if($LASTEXITCODE -ne 0){$failures+=$suite.Name}else{$passed++}
}
Write-Host "$passed passed; $skipped skipped; $($failures.Count) failed. Hardware remains unvalidated by mocks."
if($failures.Count){throw ('Failed: '+($failures -join ', '))}
