$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
. "$PSScriptRoot/../Tuning.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Rows($batch,$watts,$rate){
 for($i=1;$i -le 3;$i++){
  [pscustomobject]@{BatchId=$batch;RunIndex=$i;Test='OpenGL-test-v2';Timestamp="2026-01-0$batch`T00:00:0$i";CPUName='CPU';Runtime='4';Workers=1;Renderer='GPU';GPUName='GPU';DriverVersion='1';MemoryConfig='RAM';Plan='A';Completed=$true;StopReason=$null;GpuFramesPerSecond=($rate+$i);PowerStateAtStart=[pscustomobject]@{Devices=@([pscustomobject]@{UUID='GPU-123';Name='GPU';Current=$watts})}}
 }
}
function Sessions($records){foreach($r in $records){[pscustomobject]@{Timestamp=$r.Timestamp;Test=$r.Test;Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Name='GPU Package';Type='Power';Value=410;Parent='/gpu-nvidia/0';HardwareName='GPU'},[pscustomobject]@{Name='GPU Core';Type='Temperature';Value=60;Parent='/gpu-nvidia/0';HardwareName='GPU'})})}}}
$a=@(Rows 1 600 100);$b=@(Rows 3 540 95)
$baseline=[pscustomobject]@{Created='2026-01-02';Benchmarks=$a;Sessions=@(Sessions $a)}
$t=Get-PCBaselineComparison $baseline $b @(Sessions $b)
Assert ($t -match '3 baseline \+ 3 new' -and $t -match 'LOWER MEASURED THROUGHPUT') 'Complete batch comparison missing'
Assert ($t -match 'below both reported limits' -and $t -match '410.0') 'Power-limit context or peak median missing'
$b[0].GpuFramesPerSecond=70
Assert ((Get-PCBaselineComparison $baseline $b @(Sessions $b)) -match 'INCONCLUSIVE:') 'Noisy groups must be inconclusive'
$b=@(Rows 3 540 100)
Assert ((Get-PCBaselineComparison $baseline $b @()) -match 'Power comparison unavailable') 'Missing sessions must not invent readings'
Assert ((Get-PCBaselineComparison $baseline @($b[0]) @()) -match 'No complete three-run') 'Incomplete after batch must not compare'
$b[2].Test='OpenGL-test-v3'
Assert ((Get-PCBaselineComparison $baseline $b @()) -match 'No complete three-run') 'Mixed test revisions must not compare'
'PASS: complete matched groups, variability gate, missing coverage, revision separation and cap context'
