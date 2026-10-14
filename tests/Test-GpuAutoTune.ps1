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
 if($script:failStep -and $MHz -eq 30){throw 'Mock step write failed'}
 if($script:restoreFails -and $MHz -eq 0){throw 'Mock reset failed'}
 $script:writes++
 if($Domain -eq 0){$script:core=$MHz}else{$script:memory=$MHz}
}
function Batch($g,$core,$id,$scores){
 for($i=0;$i -lt 3;$i++){
  [pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';BatchId=$id;RunIndex=($i+1);Completed=$true;StopReason=$null;Timestamp="$id-$i";Seconds=30;GPUName='Mock GPU';Renderer='Mock GPU';CPUName='Mock CPU';Runtime='4';Workers=1;DriverVersion='1';MemoryConfig='RAM';Plan='plan-a';GpuFramesPerSecond=$scores[$i];PowerStateAtStart=[pscustomobject]@{Devices=@((Get-PCDeviceById ''));Issue=$null;ClockIssue=$null;ClockOffsets=@([pscustomobject]@{UUID=$g.Clock.UUID;Driver='1';Available=$true;CoreMHz=$core;MemoryMHz=$g.Clock.MemoryMHz})};Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';HardwareName='Mock GPU';Name='GPU Core';Type='Temperature';Value=60})})}
 }
}
function Ready {
 $g=New-PCClockGuide (Get-PCClockDevice '') (Get-PCDeviceById '') 'plan-a' $j
 Complete-PCClockGuide $g @(Batch $g 0 'baseline' @(100,101,100)) $j $p
 $g
}

function ScanBatch($g,$core,$id,$scores){
 $records=@(Batch $g $core $id $scores)
 foreach($r in $records){$r | Add-Member NoteProperty PowerStateAtEnd ($r.PowerStateAtStart | ConvertTo-Json -Depth 12 | ConvertFrom-Json)}
 $records
}
function ScanReady {
 $script:core=0;$script:memory=0
 $g=New-PCClockGuide (Get-PCClockDevice '') (Get-PCDeviceById '') 'plan-a' $j
 Enable-PCGpuAutoScan $g
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 0 'baseline' @(100,101,100)) $j $p
 $g
}
try{
 $g=ScanReady
 Assert ($g.Phase -eq 'Review' -and $script:writes -eq 0) 'Scan baseline changed hardware'
 Apply-PCClockGuide $g $j $p
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 15 'step1' @(104,105,104)) $j $p
 Assert ($g.Phase -eq 'RunningAfter' -and $script:core -eq 30 -and (Read-PCClockJournal $j).OriginalCore -eq 0) 'Step 2 lost original or did not start'
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 30 'step2' @(110,111,110)) $j $p
 Assert ($script:core -eq 45 -and (Read-PCClockGuide $p).TargetCore -eq 45) 'Step 3 not persisted or applied'
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 45 'step3' @(106,107,106)) $j $p
 Assert ($g.Phase -eq 'Restored' -and $g.ScanFinished -and $g.RecommendedCore -eq 30 -and $script:core -eq 0 -and -not (Test-Path $j)) 'Finish must restore and select measured best, not highest offset'
 $g=Read-PCClockGuide $p
 Apply-PCGpuScanRecommendation $g $j $p
 Assert ($script:core -eq 30 -and $g.Phase -eq 'Decision' -and (Read-PCClockJournal $j).OriginalCore -eq 0) 'Reviewed recommendation lost original recovery'
 Keep-PCClockGuide $g $j $p;Restore-PCClockGuide $g $j $p
 foreach($case in @('failed','hot','endmissing','enddrift','restorefail','cancel')){
  $g=ScanReady;Apply-PCClockGuide $g $j $p
  Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 15 'step1' @(104,105,104)) $j $p
  $bad=@(ScanBatch $g 30 'step2' @(110,111,110))
  switch($case){
   failed {$bad[2].Completed=$false}
   hot {$bad[0].Frames[0].Sensors[0].Value=80}
   endmissing {$bad[1].PowerStateAtEnd=$null}
   enddrift {$bad[1].PowerStateAtEnd.ClockOffsets[0].CoreMHz=15}
   restorefail {$script:restoreFails=$true;$bad[2].Completed=$false}
  }
  if($case -eq 'cancel'){Stop-PCClockGuide $g $j $p 'Cancelled'}else{Reject {Complete-PCGpuAutoScanBatch $g $bad $j $p} "$case was accepted"}
  if($case -eq 'restorefail'){
   Assert ($g.Phase -eq 'RecoveryRequired' -and (Test-Path $j)) 'Failed restore lost recovery'
   $script:restoreFails=$false;Restore-PCClockGuide (Read-PCClockGuide $p) $j $p
  }
  Assert ($script:core -eq 0 -and -not $g.ScanFinished -and $null -eq $g.RecommendedCore) "$case failed to restore/discard recommendation"
 }
 $g=ScanReady;Apply-PCClockGuide $g $j $p
 $script:failStep=$true
 Reject {Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 15 'step-write-failed' @(104,105,104)) $j $p} 'Failed next-step write was accepted'
 $script:failStep=$false
 Assert ($g.Phase -eq 'Restored' -and $script:core -eq 0 -and -not (Test-Path $j)) 'Failed step did not restore first originals'
 $g=ScanReady;$g.TargetCore=30
 Reject {Apply-PCClockGuide $g $j $p} 'First step skipped the reviewed sequence'
 Assert ($script:core -eq 0 -and -not (Test-Path $j)) 'Invalid first step wrote clocks'
 $script:core=-15;$script:memory=100
 $g=New-PCClockGuide (Get-PCClockDevice '') (Get-PCDeviceById '') 'plan-a' $j
 Enable-PCGpuAutoScan $g
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g -15 'nonzero-base' @(100,101,100)) $j $p
 Apply-PCClockGuide $g $j $p
 foreach($core in @(0,15,30)){Complete-PCGpuAutoScanBatch $g @(ScanBatch $g $core "nonzero$core" @(104,105,104)) $j $p}
 Assert ($g.Phase -eq 'Restored' -and $script:core -eq -15 -and $script:memory -eq 100) 'Nonzero starting core/memory were not preserved'
 $g=ScanReady;Apply-PCClockGuide $g $j $p
 Complete-PCGpuAutoScanBatch $g @(ScanBatch $g 15 'noisy' @(99,105,112)) $j $p
 Assert ($g.ScanFinished -and $null -eq $g.RecommendedCore -and $script:core -eq 0 -and $g.ScanResults.Count -eq 1) 'Noisy scan should stop early and recommend originals'
 $g=ScanReady;Apply-PCClockGuide $g $j $p
 foreach($core in @(15,30,45)){Complete-PCGpuAutoScanBatch $g @(ScanBatch $g $core "overlap$core" @(100,101,100)) $j $p}
 Assert ($g.ScanFinished -and $null -eq $g.RecommendedCore -and $script:core -eq 0) 'Overlapping results recommended an offset'
 $g.RecommendedCore=45;Reject {Apply-PCGpuScanRecommendation $g $j $p} 'Forged target without evidence wrote clocks'
 Assert ($script:core -eq 0) 'Forged target altered hardware'
 $g.TargetCore=60;Reject {Assert-PCGpuAutoScan $g} 'Out-of-bounds scan target accepted'
 'PASS: bounded scan sequence, original journal across steps, best measured candidate, explicit apply, cancel/failure/thermal/metadata rollback, failed-restore recovery, overlap/noise rejection and target validation'
}finally{Remove-Item $dir -Recurse -Force}
