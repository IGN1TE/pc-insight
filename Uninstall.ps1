$ErrorActionPreference='Stop'
function Assert-PCUninstallRecovery([string]$DataPath) {
    foreach($name in @('gpu-clock-restore.json','gpu-power-restore.json','restore.json')){
        if(Test-Path -LiteralPath (Join-Path $DataPath $name)){
            throw 'A settings recovery record exists. Restore saved GPU clock offsets, GPU power limits and Windows power plans in PC Insight before uninstalling.'
        }
    }
}
Add-Type -AssemblyName PresentationFramework
$mutex=$null;$locked=$false
try{
    $destination=Join-Path $env:LOCALAPPDATA 'Programs\PCInsight'
    if([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($destination).TrimEnd('\')){throw 'Run the installed Uninstall PC Insight shortcut.'}
    $marker=Join-Path $destination 'pc-insight-install.json'
    if(-not(Test-Path $marker) -or (Get-Content $marker -Raw|ConvertFrom-Json).AppId -ne 'PCInsight.PerUser'){throw 'Installation identity could not be verified.'}
    $mutex=[Threading.Mutex]::new($false,'Local\PCInsightPreview01');$locked=$mutex.WaitOne(0)
    if(-not $locked){throw 'Close PC Insight before uninstalling.'}
    $data=Join-Path $env:LOCALAPPDATA 'PCInsight'
    Assert-PCUninstallRecovery $data
    if([Windows.MessageBox]::Show('Remove PC Insight application files and shortcuts? Your reports, profiles and saved results will remain on this PC.','Uninstall PC Insight','YesNo','Question') -ne 'Yes'){return}
    $menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Insight'
    foreach($name in 'PC Insight.lnk','PC Insight (Administrator).lnk','Uninstall PC Insight.lnk'){Remove-Item (Join-Path $menu $name) -ErrorAction SilentlyContinue}
    Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PC Insight.lnk') -ErrorAction SilentlyContinue
    if((Test-Path $menu) -and (@(Get-ChildItem $menu -Force).Count -eq 0)){Remove-Item $menu}
    Set-Location ([IO.Path]::GetTempPath())
    [Environment]::CurrentDirectory=[IO.Path]::GetTempPath()
    Remove-Item $destination -Recurse -Force
    Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCInsight' -Recurse -ErrorAction SilentlyContinue
    [Windows.MessageBox]::Show('PC Insight was removed. Saved results and profiles were retained.','PC Insight')|Out-Null
}catch{[Windows.MessageBox]::Show($_.Exception.Message,'PC Insight uninstall','OK','Error')|Out-Null}
finally{if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
