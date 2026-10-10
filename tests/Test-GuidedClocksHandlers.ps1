# Cross-platform event harness: real guided UI handlers, mocked controls/worker/GPU.
$ErrorActionPreference='Stop'
foreach($m in 'Power','Results','RepeatedTests','Tuning','SessionExport','GuidedOptimize','GpuOverclock','GuidedClocks'){. "$PSScriptRoot/../$m.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-clock-handlers-'+[guid]::NewGuid());$null=New-Item -ItemType Directory $dataDir
$script:clockJournalPath=Join-Path $dataDir 'gpu-clock-restore.json';$script:gpuJournalPath=Join-Path $dataDir 'gpu-power-restore.json'
$script:ui=@{};[xml]$x=Get-Content "$PSScriptRoot/../MainWindow.xaml" -Raw
foreach($e in $x.SelectNodes('//*[@Name]')){
 $c=[pscustomobject]@{IsEnabled=$true;Text='';SelectedItem=$null;Click=$null}
 $c|Add-Member ScriptMethod Add_Click {param($handler)$this.Click=$handler}
 $ui[$e.Name]=$c
}
$script:job=$null;$script:updateJob=$null;$script:clockActionBusy=$false;$script:guide=$null;$script:snapshot='mock scan';$script:isAdministrator=$true;$script:allow=$false;$script:core=0;$script:writes=0
function Confirm($message){$script:allow}
function Show-Error($message){$script:errorSeen=$message}
function Set-Busy($busy){Refresh-PCClockGuideUI}
function Start-Task($kind){Assert ($kind -eq 'repeatgpu') 'Wrong benchmark';$script:job='mock job';Set-Busy $true}
function Cancel-Task{$script:job=$null;Interrupt-PCClockGuide 'Cancelled'}
function Get-ActivePlan{'plan-a'}
function Test-PCClockAdministrator{$true}
function Get-PCClockDevice($UUID){[pscustomobject]@{UUID='GPU-abcd';Name='Mock GPU';Driver='1';Available=$true;CoreMHz=$script:core;MemoryMHz=0;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=40}}
function Get-PCClockDevices{Get-PCClockDevice ''}
function Get-PCDeviceById($UUID){[pscustomobject]@{UUID='GPU-abcd';Name='Mock GPU';Driver='1';Current=600;Min=400;Max=600;Available=$true}}
function Set-PCClockOffset($UUID,$Domain,$MHz){$script:writes++;if($Domain -eq 0){$script:core=$MHz}}
function Batch($core){1..3|ForEach-Object{[pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';BatchId='b'+$core;RunIndex=$_;Completed=$true;StopReason=$null;Timestamp="$core-$_";Seconds=30;GPUName='Mock GPU';Renderer='Mock GPU';CPUName='CPU';Runtime='4';Workers=1;DriverVersion='1';MemoryConfig='RAM';Plan='plan-a';GpuFramesPerSecond=100+$core;PowerStateAtStart=[pscustomobject]@{Devices=@((Get-PCDeviceById ''));Issue=$null;ClockIssue=$null;ClockOffsets=@([pscustomobject]@{UUID='GPU-abcd';Driver='1';Available=$true;CoreMHz=$core;MemoryMHz=0})};Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu/0';HardwareName='Mock GPU';Name='GPU Core';Type='Temperature';Value=60})})}}}
try{
 . "$PSScriptRoot/../GuidedClocksUI.ps1"
 $ui.ClockGPU.SelectedItem=Get-PCClockDevice ''
 & $ui.CoreTrialStart.Click
 Assert (-not $script:job -and $script:writes -eq 0) 'Cancelled baseline started a worker'
 $script:allow=$true;& $ui.CoreTrialStart.Click
 Assert ($script:job -and $script:clockGuideRun -and -not $ui.ApplyClocks.IsEnabled) 'Baseline did not start/lock manual clocks'
 $script:job=$null;Complete-PCClockGuideRun @(Batch 0)
 Assert ($ui.CoreTrialApply.IsEnabled -and $script:clockGuide.Phase -eq 'Review') 'Completed baseline did not enable review'
 $script:allow=$false;& $ui.CoreTrialApply.Click
 Assert ($script:writes -eq 0) 'Cancelled apply wrote hardware'
 $script:allow=$true;& $ui.CoreTrialApply.Click
 Assert ($script:core -eq 15 -and $script:job -and $script:clockGuideRun) "Apply did not start retest: $script:errorSeen"
 & $ui.CoreTrialCancel.Click
 Assert ($script:core -eq 0 -and $script:clockGuide.Phase -eq 'Restored') 'Cancel handler did not restore'
 & $ui.CoreTrialStart.Click;$script:job=$null;Complete-PCClockGuideRun @(Batch 0)
 & $ui.CoreTrialApply.Click;$script:job=$null;Complete-PCClockGuideRun @(Batch 15)
 Assert ($ui.CoreTrialKeep.IsEnabled -and $ui.CoreTrialRestore.IsEnabled) 'Decision buttons unavailable'
 & $ui.CoreTrialKeep.Click
 Assert ($script:clockGuide.Phase -eq 'Kept' -and (Test-Path $script:clockJournalPath)) 'Keep handler lost recovery'
 & $ui.CoreTrialRestore.Click
 Assert ($script:core -eq 0 -and -not (Test-Path $script:clockJournalPath)) 'Restore handler failed'
 # Simulate a process restart after an interrupted retest; startup must not write.
 & $ui.CoreTrialStart.Click;$script:job=$null;Complete-PCClockGuideRun @(Batch 0);& $ui.CoreTrialApply.Click
 $script:job=$null;$before=$script:writes
 . "$PSScriptRoot/../GuidedClocksUI.ps1"
 Assert ($script:clockGuide.Phase -eq 'RecoveryRequired' -and $script:writes -eq $before -and $ui.CoreTrialRestore.IsEnabled) 'Restart applied settings or lost recovery'
 & $ui.CoreTrialRestore.Click
 Assert ($script:core -eq 0) 'Restart restore failed'
 'PASS: real guided UI handlers with mocked controls/worker/GPU: review cancellation, benchmark dispatch, phase gates, retest cancellation, Keep/Restore and no-write restart recovery'
}finally{Remove-Item $dataDir -Recurse -Force}
