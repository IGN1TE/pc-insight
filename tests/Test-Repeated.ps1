$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
function Assert($ok,$msg){if(-not $ok){throw $msg}}
function Row($batch,$i,$rate){[pscustomobject]@{BatchId=$batch;RunIndex=$i;RunCount=3;Test='RAM-copy-128MiB-20s-v1';Timestamp="2026-01-0$batch`T00:00:0$i";Completed=$true;StopReason=$null;MiBPerSecond=$rate;CPUName='CPU';Runtime='4';Workers=1;MemoryConfig='RAM';Plan='A';PowerStateAtStart=$null}}
$a=@((Row 1 1 100),(Row 1 2 102),(Row 1 3 101));$b=@((Row 2 1 95),(Row 2 2 101),(Row 2 3 98))
$stats=Get-PCGroupStats $a
Assert ($stats.Median -eq 101 -and $stats.Count -eq 3) 'Median incorrect'
Assert ((Get-PCBatchReport ($a+$b)) -match 'ranges overlap') 'Overlap note missing'
Assert ((Get-PCBatchReport @($a[0],$a[1])) -match 'Incomplete') 'Partial batch must be labelled'
$b[1].Plan='B'
Assert ((Get-PCBatchReport $b) -notmatch '3/3 matching') 'Mixed settings must be separated'
$script:count=0;$script:failOn=0
function Get-PCTuningCapabilities { [pscustomobject]@{Devices=@();Issue=$null} }
function Get-ActivePlan {'A'}
function Get-PCSensorFrame { [pscustomobject]@{Timestamp='2026-01-01';Sensors=@()} }
function Start-Sleep {param($Seconds,$Milliseconds)}
function Invoke-PCExtendedTest($kind){
 $script:count++
 if($script:count -eq $script:failOn){throw 'simulated failure'}
 [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{Test='RAM-copy-128MiB-20s-v1';Timestamp='2026-01-01';Completed=$true;StopReason=$null;MiBPerSecond=100;Frames=@()}}
}
$out=@(Invoke-PCRepeatedTest memory);$runs=$out[-1].Value.BatchResults
Assert ($runs.Count -eq 3 -and $runs[2].RunIndex -eq 3 -and $script:count -eq 3) 'Batch orchestration failed'
$script:count=0;$script:failOn=2
$out=@(Invoke-PCRepeatedTest memory);$runs=$out[-1].Value.BatchResults
Assert ($runs.Count -eq 2 -and -not $runs[1].Completed -and $script:count -eq 2) 'Failure must stop batch and preserve diagnostic'
'PASS: medians, partial batches, setting separation, range overlap, three-run orchestration and early failure'
