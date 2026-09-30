# Actual WPF handlers with simulated jobs. No sensors, CPU load or setting writes.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root/Power.ps1";. "$root/Monitor.ps1";. "$root/CpuTuning.ps1"
. "$PSScriptRoot/CpuTuning.Fixtures.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$script:window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('cpu-ui-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $script:dataDir
$script:ui=@{}
foreach($name in 'CpuDetect','CpuBaseline','CpuRetest','CpuStop','CpuExport','CpuNote','CpuHistory','CpuHistoryStatus','CpuPlatform','CpuStage','CpuProgress','CpuResult'){
    $ui[$name]=$window.FindName($name);Assert ($null -ne $ui[$name]) "Missing $name"
}
$script:job=$null;$script:updateJob=$null;$script:clockTrialJob=$null;$script:clockActionBusy=$false;$script:guide=$null
$script:allow=$false;$script:starts=0;$script:records=@();$script:errorText='';$script:failStart=$false
function Confirm($message){$script:review=$message;$script:allow}
function Set-Busy($busy){Update-PCCpuControls}
function Show-Error($message){$script:errorText=$message}
function Show-SensorFrame($frame){}
function Start-Job {param($ArgumentList,$ScriptBlock);if($script:failStart){throw 'Job launch failed'};$script:starts++;$script:workerArgs=$ArgumentList;[pscustomobject]@{State='Running'}}
function Receive-Job {param($Job,$ErrorAction);$script:records;$script:records=@()}
function Stop-Job {param($Job,$ErrorAction);$Job.State='Stopped'}
function Remove-Job {param($Job,[switch]$Force,$ErrorAction)}
function Click($name){$ui[$name].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
try {
    $baseline=New-CpuBaselineFixture;Save-PCCpuTrial $baseline (Join-Path $dataDir 'cpu-tuning-trials')
    . "$root/CpuTuningUI.ps1"
    Assert ($ui.CpuHistory.Items.Count -eq 1 -and $ui.CpuRetest.IsEnabled -and -not $ui.CpuBaseline.IsEnabled -and $script:starts -eq 0) 'Startup failed to restore baseline read-only'
    Assert (-not $ui.CpuNote.IsReadOnly -and $ui.CpuNote.MaxLength -eq 500) 'Settings notes are not editable or bounded'
    Click 'CpuDetect'
    Assert ($script:starts -eq 1 -and $script:jobKind -eq 'cpu-tuning' -and -not $ui.CpuRetest.IsEnabled -and $ui.CpuStop.IsEnabled) 'Detection did not reserve shared job slot'
    $script:records=@([pscustomobject]@{Kind='CpuContext';Value=(New-CpuContextFixture)});$script:job.State='Completed';Receive-PCCpuTask
    Assert ($null -eq $script:job -and $ui.CpuBaseline.IsEnabled -and $ui.CpuPlatform.Text -match 'Mock CPU') 'Detection did not release shared job or display platform'
    $ui.CpuNote.Text='Original saved BIOS profile';Click 'CpuBaseline'
    Assert ($script:starts -eq 1 -and $script:review -match 'does not apply or restore') 'Cancelled review started load or omitted CPU limitations'
    $script:allow=$true
    foreach($busySlot in 'updateJob','clockTrialJob','clockActionBusy','job'){
        Set-Variable -Name $busySlot -Scope Script -Value $true
        Click 'CpuBaseline';Assert ($script:starts -eq 1) "CPU raced $busySlot"
        Set-Variable -Name $busySlot -Scope Script -Value $null
    }
    $script:guide=[pscustomobject]@{Phase='Decision'};Click 'CpuBaseline';Assert ($script:starts -eq 1) 'CPU raced pending guided decision';$script:guide=$null
    Click 'CpuBaseline'
    Assert ($script:starts -eq 2 -and $script:workerArgs[1] -eq 'Baseline' -and -not $ui.CpuNote.IsEnabled -and $ui.CpuExport.IsEnabled) 'Baseline job gates failed'
    $active=$script:workerArgs[2];$active.BeforeRuns=@($baseline.BeforeRuns);$active.State='Ready';$active.Message='Saved baseline';Save-PCCpuTrial $active $script:cpuTrialFolder
    $script:records=@([pscustomobject]@{Kind='CpuReport';Value=$active});$script:job.State='Completed';Receive-PCCpuTask
    Assert ($ui.CpuHistory.Items.Count -eq 2 -and $ui.CpuHistory.SelectedItem.Id -eq $active.Id -and $ui.CpuRetest.IsEnabled) 'Completed baseline did not refresh saved selection'
    $ui.CpuNote.Text='External CPU profile change';Click 'CpuRetest'
    $retest=$script:workerArgs[2]
    Assert ($script:starts -eq 3 -and $retest.BeforeRuns.Count -eq 3 -and $retest.ParentId -eq $active.Id -and $retest.Id -ne $active.Id) 'Retest lost or overwrote baseline'
    Click 'CpuStop'
    Assert ((Test-Path -LiteralPath $script:cpuStopPath) -and -not $ui.CpuStop.IsEnabled -and $script:job) 'Cancel did not request cooperative shutdown'
    $script:job.State='Failed';Receive-PCCpuTask
    Assert ($null -eq $script:job -and $ui.CpuHistory.SelectedItem.Report.State -eq 'Interrupted' -and -not $ui.CpuRetest.IsEnabled) 'Abandoned checkpoint appeared complete or held job slot'
    $ui.CpuHistory.SelectedItem=@($ui.CpuHistory.Items|Where-Object Id -eq $active.Id)[0]
    function Select-PCCpuExportPath {$ui.CpuHistory.SelectedItem=@($ui.CpuHistory.Items|Where-Object Id -eq $retest.Id)[0];Join-Path $script:dataDir 'cpu-export.json'}
    Click 'CpuExport'
    $export=Get-Content (Join-Path $script:dataDir 'cpu-export.json') -Raw|ConvertFrom-Json
    Assert ($export.Experiment.Id -eq $active.Id -and $export.Experiment.BeforeRuns[2].Frames.Count -eq 61) 'Export selection changed during dialog or lost saved samples'
    function Select-PCCpuExportPath {$null};Click 'CpuExport';Assert (-not $script:errorText) 'Cancelled export failed'
    $script:failStart=$true;Click 'CpuBaseline'
    Assert ($null -eq $script:job -and $ui.CpuBaseline.IsEnabled -and $ui.CpuStage.Text -eq 'Job launch failed') 'Launch failure left controls busy'
    'PASS: CPU WPF detection, reviews, mutual exclusion, saved baseline/retest selection, cooperative cancellation, interrupted recovery and frozen export.'
}finally{$window.Close();Remove-Item $script:dataDir -Recurse -Force}
