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

function ScanBatch($core){
 $rows=@(Batch $core)
 foreach($r in $rows){$r | Add-Member NoteProperty PowerStateAtEnd ($r.PowerStateAtStart|ConvertTo-Json -Depth 12|ConvertFrom-Json)}
 $rows
}
try{
 . "$PSScriptRoot/../GuidedClocksUI.ps1"
 $ui.ClockGPU.SelectedItem=Get-PCClockDevice ''
 & $ui.GpuScanStart.Click;Assert (-not $script:job -and -not $script:clockGuide) 'Declined scan baseline started'
 $script:allow=$true;& $ui.GpuScanStart.Click
 Assert ($script:job -and $script:clockGuide.ScanMode -eq 'Core45') 'Auto scan baseline not dispatched'
 $script:job=$null;Complete-PCClockGuideRun @(ScanBatch 0)
 $script:allow=$false;& $ui.CoreTrialApply.Click;Assert ($script:writes -eq 0) 'Declined scan approval wrote hardware'
 $script:allow=$true;& $ui.CoreTrialApply.Click
 foreach($core in @(15,30,45)){
  Assert ($script:job -and $script:core -eq $core -and -not $ui.GpuScanApply.IsEnabled -and $ui.CoreTrialCancel.IsEnabled) 'Next scan worker not started or action locks failed'
  $script:job=$null;Complete-PCClockGuideRun @(ScanBatch $core)
 }
 Assert (-not $script:job -and $script:core -eq 0 -and $ui.GpuScanApply.IsEnabled -and -not $ui.CoreTrialKeep.IsEnabled) 'Scan did not return originals and offer reviewed apply'
 $writes=$script:writes;. "$PSScriptRoot/../GuidedClocksUI.ps1"
 Assert ($script:writes -eq $writes -and $ui.GpuScanApply.IsEnabled) 'Completed scan startup wrote hardware or lost recommendation'
 $script:allow=$false;& $ui.GpuScanApply.Click;Assert ($script:core -eq 0) 'Declined recommendation changed clocks'
 $script:allow=$true;& $ui.GpuScanApply.Click
 Assert ($script:core -eq 45 -and $ui.CoreTrialKeep.IsEnabled -and $ui.CoreTrialRestore.IsEnabled) 'Recommendation not applied through review'
 & $ui.CoreTrialRestore.Click
 & $ui.GpuScanStart.Click;$script:job=$null;Complete-PCClockGuideRun @(ScanBatch 0);& $ui.CoreTrialApply.Click
 $script:job=$null;Complete-PCClockGuideRun @(ScanBatch 15)
 & $ui.CoreTrialCancel.Click
 Assert ($script:core -eq 0 -and -not $ui.GpuScanApply.IsEnabled) 'Cancel during later scan step did not restore'
 & $ui.GpuScanStart.Click;$script:job=$null;Complete-PCClockGuideRun @(ScanBatch 0);& $ui.CoreTrialApply.Click
 $script:job=$null;$writes=$script:writes;. "$PSScriptRoot/../GuidedClocksUI.ps1"
 Assert ($script:clockGuide.Phase -eq 'RecoveryRequired' -and $script:writes -eq $writes -and -not $ui.GpuScanApply.IsEnabled) 'Interrupted scan resumed automatically'
 & $ui.CoreTrialRestore.Click
 & $ui.GpuScanStart.Click;$script:job=$null;Complete-PCClockGuideRun @(ScanBatch 0);& $ui.CoreTrialApply.Click
 function Start-Task($kind){$script:job=$null}
 $script:job=$null;Complete-PCClockGuideRun @(ScanBatch 15)
 Assert ($script:core -eq 0 -and -not $script:clockGuideRun -and $script:clockGuide.Phase -eq 'Restored') 'Next-worker failure did not restore originals'
 'PASS: actual automatic-scan UI review, chained workers, task locks, recommendation approval, cancellation, restart and worker-failure recovery'
}finally{Remove-Item $dataDir -Recurse -Force}
