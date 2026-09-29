# Per-user install; does not change hardware, elevation policy, or user data.
param([string]$SourcePath=$PSScriptRoot,[switch]$WaitForPreviousInstance,[switch]$LaunchAfterInstall)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$destination=Join-Path $env:LOCALAPPDATA 'Programs\PCInsight'
$parent=Split-Path $destination
$stage=Join-Path $parent ('PCInsight-stage-'+[guid]::NewGuid())
$backup=Join-Path $parent ('PCInsight-backup-'+[guid]::NewGuid())
$mutex=$null;$locked=$false;$movedOld=$false;$installed=$false
try {
    if([IO.Path]::GetFullPath($SourcePath).TrimEnd('\') -eq [IO.Path]::GetFullPath($destination).TrimEnd('\')){throw 'Extract the new ZIP into a separate folder, then run Install-PC-Insight.cmd there.'}
    $mutex=[Threading.Mutex]::new($false,'Local\PCInsightPreview01');$locked=$mutex.WaitOne($(if($WaitForPreviousInstance){15000}else{0}))
    if(-not $locked){throw 'Close PC Insight before installing or updating.'}
    if(Test-Path $destination){
        $marker=Join-Path $destination 'pc-insight-install.json'
        if(-not(Test-Path $marker) -or (Get-Content $marker -Raw|ConvertFrom-Json).AppId -ne 'PCInsight.PerUser'){throw 'The destination contains an unrecognized folder. Nothing was replaced.'}
    }
    if([IO.Path]::GetFullPath($stage).StartsWith([IO.Path]::GetFullPath($SourcePath).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Extract the ZIP outside the installation parent folder.'}
    if((Test-Path $destination) -and ((Get-Item $destination).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Installation destination is a link; no files were changed.'}
    $null=New-Item -ItemType Directory -Path $stage -Force
    Get-ChildItem -LiteralPath $SourcePath -Force | Copy-Item -Destination $stage -Recurse -Force
    if(-not(Test-Path (Join-Path $stage 'Start-App.ps1')) -or -not(Test-Path (Join-Path $stage 'PC-Insight.ps1')) -or -not(Test-Path (Join-Path $stage 'vendor\LibreHardwareMonitor\LibreHardwareMonitorLib.dll'))){throw 'Installation files are incomplete. Extract the entire ZIP.'}
    foreach($entry in (Get-Content (Join-Path $stage 'vendor\LibreHardwareMonitor\hashes.json') -Raw|ConvertFrom-Json)){
        if((Get-FileHash (Join-Path $stage ('vendor\LibreHardwareMonitor\'+$entry.Name)) -Algorithm SHA256).Hash -ne $entry.SHA256){throw 'Bundled library integrity check failed.'}
    }
    $release=Get-Content (Join-Path $stage 'version.json') -Raw|ConvertFrom-Json
    $releaseVersion=$null
    if($release.AppId -ne 'PCInsight.PerUser' -or -not [version]::TryParse([string]$release.Version,[ref]$releaseVersion)){throw 'Release version metadata is invalid.'}
    @{AppId='PCInsight.PerUser';Version=$release.Version;Installed=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $stage 'pc-insight-install.json') -Encoding UTF8
    if(Test-Path $destination){Move-Item $destination $backup;$movedOld=$true}
    try{Move-Item $stage $destination;$installed=$true}catch{if($movedOld){Move-Item $backup $destination;$movedOld=$false};throw}
    $shell=New-Object -ComObject WScript.Shell
    $menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Insight'
    $null=New-Item -ItemType Directory $menu -Force
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach($shortcut in @(
        @{Path=(Join-Path $menu 'PC Insight.lnk');Script='Start-App.ps1'},
        @{Path=(Join-Path $menu 'PC Insight (Administrator).lnk');Script='Start-Admin.ps1'},
        @{Path=(Join-Path $menu 'Uninstall PC Insight.lnk');Script='Uninstall.ps1'},
        @{Path=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'PC Insight.lnk');Script='Start-App.ps1'})){
        $link=$shell.CreateShortcut($shortcut.Path);$link.TargetPath=$exe
        $link.Arguments='-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $destination $shortcut.Script)+'"'
        $link.WindowStyle=7;$link.WorkingDirectory=$destination;$link.IconLocation=Join-Path $destination 'PCInsight.ico';$link.Save()
    }
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCInsight'
    $null=New-Item $key -Force
    $properties=@{DisplayName='PC Insight';DisplayVersion=$release.Version;InstallLocation=$destination;DisplayIcon=(Join-Path $destination 'PCInsight.ico');UninstallString=('"'+$exe+'" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $destination 'Uninstall.ps1')+'"')}
    foreach($name in $properties.Keys){$null=New-ItemProperty $key -Name $name -Value $properties[$name] -PropertyType String -Force}
    if($movedOld){Remove-Item $backup -Recurse -Force;$movedOld=$false}
    if($LaunchAfterInstall){$mutex.ReleaseMutex();$locked=$false;Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $destination 'Start-App.ps1')+'" -WaitForPreviousInstance')}
    [Windows.MessageBox]::Show('PC Insight is installed. Use the desktop or Start menu shortcut. The Administrator shortcut is available for sensors and reviewed tuning. Your existing results and recovery data were preserved.','PC Insight installation')|Out-Null
}catch{
    $prefix='Installation could not be completed. '
    if($installed){$prefix='Application files were installed, but shortcut creation or cleanup failed. You can launch Start-PC-Insight.cmd in '+$destination+'. '}
    [Windows.MessageBox]::Show($prefix+$_.Exception.Message,'PC Insight installation','OK','Error')|Out-Null
}finally{
    if(Test-Path $stage){Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue}
    if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}
}
