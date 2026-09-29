# Parser tests are read-only; no hardware workload or settings changes.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\LogSensors.ps1"
function Assert($ok,$message) { if (-not $ok) { throw $message } }
$time = [datetime]::new(2026,9,28,16,0,0)
$lines = @(',/intelcpu/0/temperature/0,/lpc/nct/temperature/0,/intelcpu/0/clock/0', 'Time,"CPU, Package","CPU Core","Core clock"', '09/28/2026 16:00:00,45,90,5200')
$s = Convert-PCLogLines $lines $time
Assert ($s.Sensors.Count -eq 3) 'Sensor count mismatch'
Assert ($s.Sensors[0].Name -eq 'CPU, Package') 'Quoted sensor names were not parsed'
Assert ($s.Sensors[0].Parent -eq '/intelcpu/0') 'CPU identity was lost'
Assert ($s.Sensors[1].Parent -eq '/lpc/nct') 'Motherboard identity was lost'
$rejected = $false
try { Convert-PCLogLines $lines ($time.AddSeconds(6)) } catch { $rejected = $true }
Assert $rejected 'Stale data was not rejected'
$rejected = $false
try { Convert-PCLogLines $lines ($time.AddSeconds(-3)) } catch { $rejected = $true }
Assert $rejected 'Future data was not rejected'
$bad = $lines.Clone(); $bad[2] = '09/28/2026 16:00:00,45'
$rejected = $false
try { Convert-PCLogLines $bad $time } catch { $rejected = $true }
Assert $rejected 'Partial row was not rejected'
$bad = $lines.Clone(); $bad[2] = '09/28/2026 16:00:00,,NaN,5200'
Assert ((Convert-PCLogLines $bad $time).Sensors.Count -eq 1) 'Missing or NaN values became readings'
Add-Type -Path "$PSScriptRoot\..\LogReader.cs"
$path = [IO.Path]::GetTempFileName()
try {
    $content = ($lines -join "`r`n") + "`r`n09/28/2026 16:00:01,99"
    [IO.File]::WriteAllText($path,$content)
    $read = [PCInsightLogReader]::Read($path)
    Assert ($read[2] -eq $lines[2]) 'Reader accepted a partially written row'
    # Verify bounded-tail reading on a large file as well.
    [IO.File]::WriteAllText($path, ($lines[0..1] -join "`r`n") + "`r`n" + (($lines[2]+"`r`n") * 10000))
    $read = [PCInsightLogReader]::Read($path)
    Assert ($read[0] -eq $lines[0] -and $read[2] -eq $lines[2]) 'Large log tail read failed'
} finally { Remove-Item -LiteralPath $path -Force }
'PASS: CSV identity, quoted names, stale/future data, missing values, partial writes and bounded tail'
# Integration regression: distance-to-limit is not an absolute temperature.
$path = [IO.Path]::GetTempFileName()
try {
    $timeText = (Get-Date).ToString('MM/dd/yyyy HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
    [IO.File]::WriteAllText($path, ",/intelcpu/0/temperature/0,/intelcpu/0/temperature/1`r`nTime,CPU Package,P-Core Distance to TjMax`r`n$timeText,32,76`r`n")
    $frame = Get-PCLogFrame $path
    Assert ($null -eq $frame.Issue -and $frame.CPUCelsius -eq 32) 'Headroom was counted as CPU temperature'
} finally { Remove-Item -LiteralPath $path -Force }
. "$PSScriptRoot\..\Power.ps1"
$old = [pscustomobject]@{ value=@([pscustomobject]@{Test='single';MiBPerSecond=2400});Count=1 }
$flat = @(Expand-PCHistory @($old,[pscustomobject]@{Test='parallel';MiBPerSecond=31000}))
Assert ($flat.Count -eq 2 -and $flat[0].Test -eq 'single') 'Wrapped history migration failed'
'PASS: actual-temperature selection and wrapped-history recovery'
