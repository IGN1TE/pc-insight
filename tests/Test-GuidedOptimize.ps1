$ErrorActionPreference='Stop'
foreach($file in 'Power','Results','RepeatedTests','Tuning','SessionExport','GuidedOptimize'){. "$PSScriptRoot/../$file.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($action,$message){$rejected=$false;try{& $action|Out-Null}catch{$rejected=$true};Assert $rejected $message}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-guide-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory $dir
$j=Join-Path $dir 'journal.json';$b=Join-Path $dir 'baseline.json';$gpath=Join-Path $dir 'guide.json'
$script:fixtureJournal=$j;$script:fixtureBaseline=$b
$script:watts=600.0;$script:writes=0;$script:rejectRestore=$false;$script:plan='plan-a';$script:failApply=$false
function Get-ActivePlan{$script:plan}
function Invoke-PCNvidia([string[]]$Arguments){
 if($Arguments[0] -like '--query*'){return "GPU-12345678-abcd-abcd-abcd-123456789012, NVIDIA Test, 1, $script:watts, 600, 400, 600"}
 Assert ((Test-Path $script:fixtureJournal) -and (Test-Path $script:fixtureBaseline)) 'Write happened before recovery and baseline saved'
 $value=[double]::Parse($Arguments[3],[Globalization.CultureInfo]::InvariantCulture)
 if($script:rejectRestore -and $value -eq 600){throw 'Simulated restore failure'}
 $script:writes++
 if($script:failApply){$script:failApply=$false;throw 'Simulated apply failure'}
 $script:watts=$value
 'ok'
}
function Batch($guide,$watts,$batch,$start,$scores){
 for($i=0;$i -lt 3;$i++){
  $device=$guide.Device.PSObject.Copy();$device.Current=$watts
  [pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';BatchId=$batch;RunIndex=($i+1);RunCount=3;Completed=$true;StopReason=$null;Timestamp=$start.AddSeconds($i).ToString('o');GPUName=$guide.Device.Name;Renderer=$guide.Device.Name;CPUName='CPU';Runtime='4';Workers=1;DriverVersion='1';MemoryConfig='RAM';Plan='plan-a';GpuFramesPerSecond=$scores[$i];PowerStateAtStart=[pscustomobject]@{Devices=@($device);Issue=$null};Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';HardwareName=$guide.Device.Name;Name='GPU Core';Type='Temperature';Value=60})})}
 }
}
function ReadyGuide {
 $g=New-PCGuide @(Get-PCPowerDevices) 'plan-a' $j
 $g.Before=@(Batch $g 600 'before' ([datetime]'2026-01-01') @(100,101,100))
 $g.Baseline=[pscustomobject]@{Created='2026-01-02';Benchmarks=$g.Before;Sessions=$g.Before}
 $g.Phase='Review'
 return $g
}
try{
 $guide=ReadyGuide
 Assert ($guide.TargetWatts -eq 540 -and $script:writes -eq 0) 'Detection wrote or wrong target'
 Assert-PCGuideBatch $guide $guide.Before 600
 Reject {New-PCGuide @((Get-PCPowerDevices),(Get-PCPowerDevices)) 'plan-a' $j} 'Multiple NVIDIA GPUs accepted'
 Save-PCGuide $guide $gpath
 Assert ((Read-PCGuide $gpath).Phase -eq 'Review') 'State roundtrip failed'
 $guide.Before[1].RunIndex=1
 Reject {Assert-PCGuideBatch $guide $guide.Before 600} 'Duplicate run accepted'
 $guide.Before[1].RunIndex=2
 $script:plan='plan-b'
 Reject {Apply-PCGuide $guide $j $b $gpath} 'Changed plan allowed a write'
 Assert ($script:writes -eq 0) 'Changed plan wrote'
 $script:plan='plan-a'
 Apply-PCGuide $guide $j $b $gpath
 Assert ($guide.Phase -eq 'RunningAfter' -and $script:watts -eq 540) 'Apply did not verify target'
 Reject {New-PCGuide @(Get-PCPowerDevices) 'plan-a' $j} 'Pending recovery allowed new guide'
 Stop-PCGuide $guide $j $gpath 'Cancelled'
 Assert ($guide.Phase -eq 'Restored' -and $script:watts -eq 600 -and -not(Test-Path $j)) 'Cancellation did not restore'
 $guide=ReadyGuide;Apply-PCGuide $guide $j $b $gpath
 $guide.After=@(Batch $guide 540 'after' ([datetime]'2026-01-03') @(89,90,91))
 Assert ((Get-PCGuideVerdict $guide).Title -eq 'Lower measured throughput') 'Performance regression not reported'
 $guide.After=@(Batch $guide 540 'after' ([datetime]'2026-01-03') @(100,101,100))
 Assert ((Get-PCGuideVerdict $guide).Title -match 'overlap') 'Overlapping results not inconclusive'
 $guide.After=@(Batch $guide 540 'after' ([datetime]'2026-01-03') @(90,110,100))
 Assert ((Get-PCGuideVerdict $guide).Title -match 'variability') 'Noisy result not inconclusive'
 $guide.After[0].GPUName='Other GPU'
 Reject {Get-PCGuideVerdict $guide} 'Different renderer accepted'
 $script:rejectRestore=$true
 Stop-PCGuide $guide $j $gpath 'Simulated failed test'
 Assert ($guide.Phase -eq 'RecoveryRequired' -and (Test-Path $j)) 'Failed recovery lost journal'
 $script:rejectRestore=$false
 Restore-PCGuide $guide $j $gpath
 Assert ($guide.Phase -eq 'Restored' -and $script:watts -eq 600) 'Recovery retry failed'
 $guide=ReadyGuide;$script:failApply=$true
 Reject {Apply-PCGuide $guide $j $b $gpath} 'Failed apply was hidden'
 Assert ($guide.Phase -eq 'Restored' -and $script:watts -eq 600) 'Apply failure did not restore'
 $guide=ReadyGuide;$guide.Phase='RunningBaseline';$writes=$script:writes
 Stop-PCGuide $guide $j $gpath 'Baseline cancelled'
 Assert ($guide.Phase -eq 'Interrupted' -and $script:writes -eq $writes) 'Baseline cancellation wrote settings'
 $guide=ReadyGuide;$guide.Phase='RunningBaseline';$writes=$script:writes
 $null=Resume-PCGuideState $guide $j
 Assert ($guide.Phase -eq 'Interrupted' -and $script:writes -eq $writes) 'Startup without change wrote settings'
 $guide=ReadyGuide;Apply-PCGuide $guide $j $b $gpath;$writes=$script:writes
 $null=Resume-PCGuideState $guide $j
 Assert ($guide.Phase -eq 'RecoveryRequired' -and $script:writes -eq $writes -and (Test-Path $j)) 'Startup lost recovery or changed hardware'
 Restore-PCGuide $guide $j $gpath
 'PASS: detection, persistence, exact GPU/run matching, changed plans, saved recovery before writes, apply/readback, cancel restoration, verdicts, failed restore and retry, failed apply recovery'
}finally{Remove-Item $dir -Recurse -Force}
