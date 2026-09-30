# Windows WPF: actual button/timer handlers, simulated job and GPU. No hardware access.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root/GpuOverclock.ps1"
. "$root/GpuClockTrial.ps1"
. "$root/Tuning.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-trial-ui-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dataDir
$script:ui=@{}
foreach($name in 'ClockTrialTelemetryRun','ClockTrialTelemetrySensor','ClockTrialTelemetryChart','ClockTrialTelemetryScale','ClockTrialTelemetryTime','ClockTrialTelemetrySummary','ClockTrialHistory','ClockTrialReference','LoadClockTrialOffsets','ExportSavedClockTrial','ExportClockTrialComparison','ClockTrialHistoryStatus','ClockTrialSavedResult','ClockTrialComparisonResult','DetectClocks','ClockGPU','ClockInfo','CoreOffset','MemoryOffset','ApplyClocks','RestoreClocks','ClockStatus','ClockTrialMode','StartClockTrial','StopClockTrial','ExportClockTrial','ClockTrialStage','ClockTrialProgress','ClockTrialResult','Cancel','SensorCancel'){
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
function New-HistoryFixture([int]$Core,[double]$Score){
    $context=[pscustomobject]@{UUID=$script:device.UUID;Driver='mock';Plan='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';PowerLimitWatts=450}
    $r=[pscustomobject]@{Schema=2;Kind='PCInsight.GpuClockTrial';Id=[guid]::NewGuid().ToString('N');Started=[datetimeoffset]::Now.AddSeconds($Core).ToString('o');State='Completed';Device=($script:device|Select-Object *);Requested=[pscustomobject]@{CoreMHz=$Core;MemoryMHz=125};RunCount=3;Environment=$context;BeforeRuns=@();AfterRuns=@();BeforeSummary=$null;AfterSummary=$null;ChangePercent=$null;Comparison=$null;ComparisonReasons=@();Restoration='Verified';Message='Mock fixture';Limitations='Mock data'}
    foreach($side in 'Before','After'){
        $rate=if($side -eq 'Before'){100}else{$Score}
        $r.($side+'Runs')=@(1..3|ForEach-Object {[pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';Seconds=30;Runtime='4.0';Renderer='Mock GPU/PCIe';GPUName='Mock GPU';WarmupSeconds=5;Completed=$true;StopReason=$null;DrawsPerSecond=($rate+$_-2);PeakGpuC=65;TemperatureSamples=30;RunIndex=$_;StartGpuC=50;EnvironmentBefore=$context;EnvironmentAfter=$context;Eligible=$true}})
        $r.($side+'Summary')=Get-PCClockTrialSummary $r.($side+'Runs')
    }
    foreach($run in @($r.BeforeRuns)+@($r.AfterRuns)){
        $frames=@(0..2|ForEach-Object {[pscustomobject]@{Timestamp=([datetimeoffset]'2026-01-01T12:00:00Z').AddSeconds($_).ToString('o');QuerySeconds=0.1;Issue=$null;Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Identifier='/gpu/temperature/0';HardwareName='Mock GPU';Type='Temperature';Name='GPU Core';Value=(50+$_)},[pscustomobject]@{Parent='/gpu-nvidia/0';Identifier='/gpu/clock/0';HardwareName='Mock GPU';Type='Clock';Name='GPU Core';Value=(2000+$_)})}})
        $run|Add-Member NoteProperty Telemetry (ConvertTo-PCClockTrialTelemetry ([pscustomobject]@{GPUName='Mock GPU';Frames=$frames}))
    }
    Complete-PCClockTrialComparison $r;$r
}
try{
    $a=New-HistoryFixture 50 110;$b=New-HistoryFixture 75 120
    Save-PCClockTrialHistory $a (Join-Path $dataDir 'gpu-clock-trials');Save-PCClockTrialHistory $b (Join-Path $dataDir 'gpu-clock-trials')
    . "$root/GpuOverclockUI.ps1"
    . "$root/GpuClockTrialUI.ps1"
    . "$root/GpuClockTrialHistoryUI.ps1"
    . "$root/GpuClockTrialTelemetryUI.ps1"
    Assert ($ui.ClockTrialTelemetryRun.Items.Count -eq 6 -and $ui.ClockTrialTelemetrySensor.Items.Count -eq 2 -and $ui.ClockTrialTelemetryChart.Children.Count -eq 4) 'Saved telemetry selectors or graph were not initialized'
    $ui.ClockTrialTelemetrySensor.SelectedIndex=1
    Assert ($ui.ClockTrialTelemetryScale.Text -match 'MHz' -and $ui.ClockTrialTelemetrySummary.Text.Contains(('{0:N1}' -f 2000))) 'Sensor selection did not redraw the clock graph'
    $ui.ClockTrialTelemetryRun.SelectedIndex=4
    Assert ($ui.ClockTrialTelemetryRun.SelectedItem.Key -eq 'After:2' -and $ui.ClockTrialTelemetrySensor.SelectedItem.Type -eq 'Clock') 'Run change lost the selected sensor'
    Assert (-not $ui.StartClockTrial.IsEnabled -and $script:writeCount -eq 0) 'Undetected trial enabled or startup wrote'
    Assert ($ui.ClockTrialHistory.Items.Count -eq 2 -and -not $ui.LoadClockTrialOffsets.IsEnabled -and $ui.ExportSavedClockTrial.IsEnabled) 'Saved history was not loaded read-only on startup'
    Assert ($ui.ClockTrialReference.Items.Count -eq 1 -and $ui.ClockTrialReference.SelectedItem.Id -ne $ui.ClockTrialHistory.SelectedItem.Id -and $ui.ClockTrialComparisonResult.Text -match '9.09') 'History comparison or self-reference exclusion failed'
    Click 'DetectClocks'
    Assert ($ui.StartClockTrial.IsEnabled) 'Detected trial unavailable'
    Click 'LoadClockTrialOffsets'
    Assert ($ui.CoreOffset.Text -eq '75' -and $ui.MemoryOffset.Text -eq '125' -and $script:writeCount -eq 0 -and $script:starts -eq 0) 'Saved offset load applied hardware or started a trial'
    function Select-PCClockTrialExportPath($Name){$ui.ClockTrialHistory.SelectedItem=$script:clockTrialCatalog|Where-Object Id -eq $a.Id;Join-Path $dataDir 'comparison-export.json'}
    Click 'ExportClockTrialComparison'
    $export=Get-Content (Join-Path $dataDir 'comparison-export.json') -Raw|ConvertFrom-Json
    Assert ($export.Current.Id -eq $b.Id -and $export.Comparison.ChangePercent -eq 9.09) 'Export did not freeze the selected comparison before the dialog'
    function Select-PCClockTrialExportPath($Name){$null}
    Click 'ExportSavedClockTrial';Assert (@(Get-ChildItem $dataDir -Filter '*export.json').Count -eq 1) 'Cancelled export wrote another file'
    $ui.CoreOffset.Text='50';$ui.MemoryOffset.Text='100';Click 'StartClockTrial'
    Assert ($script:starts -eq 0 -and -not $script:clockActionBusy) 'Cancelled review started job or stayed busy'
    Assert ($script:review.Contains($script:device.UUID) -and $script:review.Contains('50 MHz') -and $script:review.Contains('restores the originals')) 'Review omitted target or automatic restoration'
    Assert ($script:review.Contains('3 baseline run(s)') -and $script:review.Contains('about 5 minutes')) 'Default repeated trial not reviewed'
    $script:allow=$true;Click 'StartClockTrial'
    Assert ($script:starts -eq 1 -and $script:clockTrialJob -and $ui.StopClockTrial.IsEnabled -and -not $ui.ApplyClocks.IsEnabled -and -not $ui.StartClockTrial.IsEnabled -and -not $ui.Cancel.IsEnabled) 'Running trial gates failed'
    Assert ($script:workerArgs[-1] -eq 3 -and -not $ui.ClockTrialMode.IsEnabled) 'Repeated mode not passed to worker or editable while running'
    Assert (-not $ui.LoadClockTrialOffsets.IsEnabled -and $ui.ExportSavedClockTrial.IsEnabled) 'Busy trial should block input loading but allow saved export'
    $ui.ClockTrialTelemetryRun.SelectedIndex=2
    Assert ($ui.ClockTrialTelemetryChart.Children.Count -eq 4 -and $script:writeCount -eq 0 -and $script:starts -eq 1) 'Saved graph browsing changed an active trial'
    Click 'LoadClockTrialOffsets';Assert ($ui.CoreOffset.Text -eq '50' -and $script:writeCount -eq 0) 'Saved input load raced the active trial'
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
    Assert (-not $ui.LoadClockTrialOffsets.IsEnabled) 'Pending recovery allowed saved offset loading'
    $legacy=$script:clockTrialCatalog[0];foreach($run in @($legacy.Report.BeforeRuns)+@($legacy.Report.AfterRuns)){$run.PSObject.Properties.Remove('Telemetry')}
    $ui.ClockTrialHistory.SelectedItem=$legacy;Show-PCClockTrialTelemetry
    Assert ($ui.ClockTrialTelemetryChart.Children.Count -eq 0 -and -not $ui.ClockTrialTelemetrySensor.IsEnabled -and $ui.ClockTrialTelemetrySummary.Text -match 'no retained') 'Legacy selection left a stale graph visible'
    $ui.ClockTrialHistory.SelectedIndex=-1
    Assert ($ui.ClockTrialTelemetryChart.Children.Count -eq 0 -and $ui.ClockTrialTelemetryRun.Items.Count -eq 0) 'Clearing history retained another experiment graph'
    'PASS: actual WPF trial/history/telemetry selection and graphs, legacy clearing, read-only loading/browsing, frozen/cancelled exports, busy gates and worker restoration (mock hardware).'
}finally{
    if($script:clockTrialTimer){$script:clockTrialTimer.Stop()}
    $window.Close();Remove-Item $dataDir -Recurse -Force
}
