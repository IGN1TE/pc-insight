$ErrorActionPreference='Stop'
. "$PSScriptRoot/../LiveMonitor.ps1"
function Assert($ok,$message) { if (-not $ok) { throw $message } }
function Frames($count,$load,$memory) {
    for($i=0;$i -lt $count;$i++) { [pscustomobject]@{Timestamp=([datetimeoffset]'2026-01-01T00:00:00Z').AddSeconds($i).ToString('o');CPUCelsius=40;MemoryUsedPercent=$memory;Sensors=@([pscustomobject]@{Parent='/intelcpu/0';Name='CPU Total';Type='Load';Value=$load});Issue=$null} }
}
$a=@(Frames 12 95 93)
$t=(Get-PCMeasuredInsights $a)-join "`n"
Assert ($t -match 'CPU LOAD CANDIDATE' -and $t -match 'MEMORY PRESSURE CANDIDATE') 'Sustained usage should trigger candidates'
Assert ($t -match 'GPU load unavailable') 'Missing GPU must be explicit'
$b=@(Frames 12 20 $null);$b[0].Sensors[0].Value=100
$t=(Get-PCMeasuredInsights $b)-join "`n"
Assert ($t -notmatch 'CPU LOAD CANDIDATE' -and $t -match 'RAM usage unavailable') 'Spike and missing RAM must not trigger'
$t=(Get-PCMeasuredInsights @($a | Select-Object -First 4))-join "`n"
Assert ($t -match 'at least 10 samples' -and $t -notmatch 'CANDIDATE') 'Short windows must defer diagnosis'
$b[0].CPUCelsius=86
Assert (((Get-PCMeasuredInsights $b)-join "`n") -match 'TEMPERATURE REVIEW') 'Temperature review missing'
# Exercise a long session without real sleeps or hardware. Stop at 305 frames.
$script:n=0
$signal=Join-Path ([IO.Path]::GetTempPath()) ('pc-test-'+[guid]::NewGuid()+'.signal')
function Get-PCSensorFrame { $script:n++; if($script:n -eq 305){Set-Content $signal stop}; (Frames 1 25 30) }
function Add-PCMemorySample($frame) { $frame }
function Start-Sleep { param($Milliseconds) }
try {
 $output=@(Invoke-PCContinuousSession $signal)
 $result=$output[-1].Value
 Assert ($result.TotalQueries -eq 305 -and $result.Frames.Count -eq 300) 'Rolling retention must be bounded'
 Assert ($output[-1].Kind -eq 'Result' -and $result.Completed) 'Graceful stop must return a result'
} finally { Remove-Item $signal -ErrorAction SilentlyContinue }
'Live monitoring diagnostics and bounded retention tests passed'
