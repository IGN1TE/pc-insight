# Windows WPF: actual button/timer handlers, simulated job and GPU. No hardware access.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root/GpuOverclock.ps1"
. "$root/GpuClockTrial.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-trial-ui-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dataDir
$script:ui=@{}
foreach($name in 'DetectClocks','ClockGPU','ClockInfo','CoreOffset','MemoryOffset','ApplyClocks','RestoreClocks','ClockStatus','ClockTrialMode','StartClockTrial','StopClockTrial','ExportClockTrial','ClockTrialStage','ClockTrialProgress','ClockTrialResult','Cancel','SensorCancel'){
    $ui[$name]=$window.FindName($name);Assert ($null -ne $ui[$name]) "Missing $name"
}
$script:job=$null;$script:updateJob=$null;$script:guide=$null;$script:isAdministrator=$true
$script:allow=$false;$script:starts=0;$script:records=@();$script:writeCount=0;$script:lastError=''
$script:device=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Label='Mock GPU';Driver='mock';Available=$true;CoreMHz=0;MemoryMHz=0;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
function Get-PCClockDevices {$script:device|Select-Object *}
function Get-PCClockDevice($UUID){$script:device|Select-Object *}
function Test-PCClockAdministrator {$script:isAdministrator}
function Set-PCClockOffset($UUID,$Domain,$MHz){$script:writeCount++;if($Domain -eq 0){$script:device.CoreMHz=$MHz}else{$script:device.MemoryMHz=$MHz}}
function Set-Busy($Busy){Update-PCClockControlState $Busy}
function Confirm($message){$script:review=$message;$script:allow}
function Show-Error($message){$script:lastError=$message}
function Start-Job {param($ArgumentList,$ScriptBlock);$script:starts++;$script:workerArgs=$ArgumentList;[pscustomobject]@{State='Running';ChildJobs=@([pscustomobject]@{Error=@()})}}
function Receive-Job {param($Job,$ErrorAction);$script:records;$script:records=@()}
function Remove-Job {param($Job,[switch]$Force,$ErrorAction)}
function Click($Name){$ui[$Name].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
try{
    . "$root/GpuOverclockUI.ps1"
    . "$root/GpuClockTrialUI.ps1"
    Assert (-not $ui.StartClockTrial.IsEnabled -and $script:writeCount -eq 0) 'Undetected trial enabled or startup wrote'
    Click 'DetectClocks'
    Assert ($ui.StartClockTrial.IsEnabled) 'Detected trial unavailable'
    $ui.CoreOffset.Text='50';$ui.MemoryOffset.Text='100';Click 'StartClockTrial'
    Assert ($script:starts -eq 0 -and -not $script:clockActionBusy) 'Cancelled review started job or stayed busy'
    Assert ($script:review.Contains($script:device.UUID) -and $script:review.Contains('50 MHz') -and $script:review.Contains('restores the originals')) 'Review omitted target or automatic restoration'
    Assert ($script:review.Contains('3 baseline run(s)') -and $script:review.Contains('about 5 minutes')) 'Default repeated trial not reviewed'
    $script:allow=$true;Click 'StartClockTrial'
    Assert ($script:starts -eq 1 -and $script:clockTrialJob -and $ui.StopClockTrial.IsEnabled -and -not $ui.ApplyClocks.IsEnabled -and -not $ui.StartClockTrial.IsEnabled -and -not $ui.Cancel.IsEnabled) 'Running trial gates failed'
    Assert ($script:workerArgs[-1] -eq 3 -and -not $ui.ClockTrialMode.IsEnabled) 'Repeated mode not passed to worker or editable while running'
    Click 'ApplyClocks';Assert ($script:writeCount -eq 0) 'Manual apply raced trial'
    Click 'StopClockTrial';Assert ((Test-Path $script:clockTrialStopPath) -and -not $ui.StopClockTrial.IsEnabled) 'Stop did not request cooperative cancellation'
    # A failed child after apply must use the retained journal to recover.
    $j=[pscustomobject]@{Schema=1;Kind='PCInsight.NvidiaClockOffsets';Pstate=0;UUID=$script:device.UUID;Name='Mock GPU';Driver='mock';OriginalCore=0;OriginalMemory=0;LastCore=50;LastMemory=100;State='Applied'}
    Save-PCClockJournal $j $script:clockJournalPath;$script:device.CoreMHz=50;$script:device.MemoryMHz=100
    $script:clockTrialJob.State='Failed';Receive-PCClockTrial
    Assert (-not $script:clockTrialJob -and -not $script:clockActionBusy -and -not (Test-Path $script:clockJournalPath) -and $script:device.CoreMHz -eq 0 -and $script:device.MemoryMHz -eq 0) 'Failed worker recovery failed'
    Assert ($ui.StartClockTrial.IsEnabled -and -not $ui.StopClockTrial.IsEnabled -and $ui.ClockTrialResult.Text -match 'Restored') 'Interrupted result/control state incorrect'
    $ui.ClockTrialMode.SelectedIndex=1;$ui.CoreOffset.Text='50';$ui.MemoryOffset.Text='100';Click 'StartClockTrial'
    Assert ($script:workerArgs[-1] -eq 1 -and $script:review.Contains('about 90 seconds')) 'Quick trial mode was not honored'
    $script:clockTrialJob.State='Completed';Receive-PCClockTrial
    $script:isAdministrator=$false;Update-PCClockControlState
    Assert (-not $ui.StartClockTrial.IsEnabled) 'Nonadmin trial enabled'
    $script:isAdministrator=$true;Save-PCClockJournal $j $script:clockJournalPath;Update-PCClockControlState
    Assert (-not $ui.StartClockTrial.IsEnabled -and $ui.RestoreClocks.IsEnabled) 'Pending recovery allowed trial or blocked restore'
    'PASS: actual WPF trial review/cancel/start/stop handlers, busy gates, failed worker restoration and recovery/admin controls (mock hardware).'
}finally{
    if($script:clockTrialTimer){$script:clockTrialTimer.Stop()}
    $window.Close();Remove-Item $dataDir -Recurse -Force
}
