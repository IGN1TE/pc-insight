$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Run($batch,$index,$rate,$test){[pscustomobject]@{BatchId=$batch;RunIndex=$index;Test=$test;Timestamp="2026-01-0$batch`T00:00:0$index";CPUName='CPU';Runtime='4';Workers=1;Renderer='GPU';DriverVersion='1';Plan='A';Completed=$true;GpuFramesPerSecond=$rate;StopReason=$null;PowerStateAtStart=$null}}
$old=@((Run 1 1 20518.89 'OpenGL-v1'),(Run 1 2 19578.61 'OpenGL-v1'),(Run 1 3 23144.52 'OpenGL-v1'))
$text=Get-PCBatchReport $old
Assert ($text -match 'HIGH VARIABILITY' -and $text -match '17.4%') 'Observed user batch must be flagged'
$new=@((Run 2 1 100 'OpenGL-v2'),(Run 2 2 101 'OpenGL-v2'),(Run 2 3 102 'OpenGL-v2'))
$text=Get-PCBatchReport ($old+$new)
Assert ($text -notmatch 'LATEST BATCH COMPARISON') 'Old and new GPU workloads must not compare'
$noisy=@((Run 3 1 90 'OpenGL-v2'),(Run 3 2 100 'OpenGL-v2'),(Run 3 3 115 'OpenGL-v2'))
Assert ((Get-PCBatchReport ($new+$noisy)) -match 'COMPARISON INCONCLUSIVE') 'Noisy batch must not imply tuning gain'
'PASS: measured 17.4% variability flagged, revision isolation and inconclusive noisy comparisons'
