$ErrorActionPreference='Stop'
foreach($module in 'Power','Results','RepeatedTests','Tuning','SessionExport','GuidedOptimize','GpuOverclock','GuidedClocks'){. "$PSScriptRoot/../$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Assert $failed $message}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-core-guide-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory $dir
$j=Join-Path $dir 'clock.json';$p=Join-Path $dir 'trial.json';$script:fixtureJournal=$j
$script:core=0;$script:memory=0;$script:writes=0;$script:restoreFails=$false;$script:plan='plan-a'
function Get-ActivePlan {$script:plan}
function Test-PCClockAdministrator {$true}
function Get-PCClockDevice($UUID){[pscustomobject]@{UUID='GPU-12345678-abcd-abcd-abcd-123456789012';Name='Mock GPU';Driver='1';Available=$true;CoreMHz=$script:core;MemoryMHz=$script:memory;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=40}}
function Get-PCDeviceById($UUID){[pscustomobject]@{UUID='GPU-12345678-abcd-abcd-abcd-123456789012';Name='Mock GPU';Driver='1';Current=600;Min=400;Max=600;Available=$true}}
function Set-PCClockOffset($UUID,$Domain,$MHz){
 Assert (Test-Path $script:fixtureJournal) 'Hardware write before original journal'
 if($script:restoreFails -and $MHz -eq 0){throw 'Mock reset failed'}
 $script:writes++
 if($Domain -eq 0){$script:core=$MHz}else{$script:memory=$MHz}
}
function Batch($g,$core,$id,$scores){
 for($i=0;$i -lt 3;$i++){
  [pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';BatchId=$id;RunIndex=($i+1);Completed=$true;StopReason=$null;Timestamp="$id-$i";Seconds=30;GPUName='Mock GPU';Renderer='Mock GPU';CPUName='Mock CPU';Runtime='4';Workers=1;DriverVersion='1';MemoryConfig='RAM';Plan='plan-a';GpuFramesPerSecond=$scores[$i];PowerStateAtStart=[pscustomobject]@{Devices=@((Get-PCDeviceById ''));Issue=$null;ClockIssue=$null;ClockOffsets=@([pscustomobject]@{UUID=$g.Clock.UUID;Driver='1';Available=$true;CoreMHz=$core;MemoryMHz=0})};Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';HardwareName='Mock GPU';Name='GPU Core';Type='Temperature';Value=60})})}
 }
}
function Ready {
 $g=New-PCClockGuide (Get-PCClockDevice '') (Get-PCDeviceById '') 'plan-a' $j
 Complete-PCClockGuide $g @(Batch $g 0 'baseline' @(100,101,100)) $j $p
 $g
}
try{
 $g=Ready;Assert ($g.Phase -eq 'Review' -and $script:writes -eq 0 -and $g.TargetCore -eq 15) 'Baseline wrote clocks or wrong proposed step'
 Assert ((Read-PCClockGuide $p).TargetCore -eq 15) 'Persistence lost trial identity'
 $bad=@(Batch $g 0 'bad' @(100,100,100));$bad[1].PowerStateAtStart.ClockOffsets[0].MemoryMHz=100
 Reject {Assert-PCClockGuideBatch $g $bad 0} 'Changed memory accepted'
 $bad=@(Batch $g 0 'bad' @(100,100,100));$bad[1].RunIndex=1
 Reject {Assert-PCClockGuideBatch $g $bad 0} 'Duplicate run accepted'
 $bad=@(Batch $g 0 'bad' @(100,100,100));$bad[1].Seconds=39
 Reject {Assert-PCClockGuideBatch $g $bad 0} 'Mismatched duration accepted'
 $script:plan='changed';Reject {Apply-PCClockGuide $g $j $p} 'Changed plan accepted';Assert ($script:writes -eq 0) 'Changed plan wrote hardware';$script:plan='plan-a'
 Apply-PCClockGuide $g $j $p
 Assert ($g.Phase -eq 'RunningAfter' -and $script:core -eq 15 -and $script:memory -eq 0) 'Apply/retest transition failed'
 Complete-PCClockGuide $g @(Batch $g 15 'after' @(104,105,104)) $j $p
 Assert ($g.Phase -eq 'Decision' -and $g.Summary -match 'Higher measured' -and $g.Summary -match 'temperature peaks') 'Valid retest not summarized'
 Keep-PCClockGuide $g $j $p
 Assert ($g.Phase -eq 'Kept' -and (Test-Path $j)) 'Keep lost recovery'
 Restore-PCClockGuide $g $j $p
 Assert ($g.Phase -eq 'Restored' -and $script:core -eq 0 -and -not (Test-Path $j)) 'Explicit restore failed'
 $g=Ready;Apply-PCClockGuide $g $j $p
 Stop-PCClockGuide $g $j $p 'Cancelled'
 Assert ($g.Phase -eq 'Restored' -and $script:core -eq 0) 'Retest cancellation did not restore'
 $g=Ready;Apply-PCClockGuide $g $j $p
 $bad=@(Batch $g 15 'failed' @(100,100,100));$bad[2].Completed=$false
 Reject {Complete-PCClockGuide $g $bad $j $p} 'Failed retest accepted'
 Assert ($g.Phase -eq 'Restored' -and $script:core -eq 0) 'Failed retest did not restore'
 $g=Ready;Apply-PCClockGuide $g $j $p;$script:restoreFails=$true
 Stop-PCClockGuide $g $j $p 'Cancelled'
 Assert ($g.Phase -eq 'RecoveryRequired' -and (Test-Path $j)) 'Failed restoration did not retain recovery'
 $loaded=Read-PCClockGuide $p;$script:restoreFails=$false
 Restore-PCClockGuide $loaded $j $p
 Assert ($script:core -eq 0) 'Recovery after reload failed'
 $g=Ready;Apply-PCClockGuide $g $j $p
 Complete-PCClockGuide $g @(Batch $g 15 'overlap' @(100,101,100)) $j $p
 Assert ($g.Summary -match 'overlap') 'Overlapping results claimed a gain'
 Restore-PCClockGuide $g $j $p
 $g=Ready;Stop-PCClockGuide $g $j $p 'Review cancelled'
 Assert ($g.Phase -eq 'Interrupted' -and -not (Test-Path $j)) 'Review cancellation wrote recovery'
 $script:core=15
 Reject {Restore-PCClockGuide $g $j $p} 'Missing journal invented a restored state'
 'PASS: zero-write baseline, single-step trial, strict batch/clock matching, timing/plan drift, decision/keep/restore, cancel/failure rollback, retained recovery and reload, temperature summary and missing-journal protection'
}finally{Remove-Item $dir -Recurse -Force}
