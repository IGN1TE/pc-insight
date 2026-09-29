$ErrorActionPreference='Stop'
foreach($file in 'SessionExport','SessionDetails','SessionChart'){. "$PSScriptRoot/../$file.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Frame($time,$value,$issue=$null){[pscustomobject]@{Timestamp=$time;Issue=$issue;Sensors=@([pscustomobject]@{Parent='/gpu/0';Identifier='/gpu/0/load';HardwareName='GPU';Name='GPU Core';Type='Load';Value=$value})}}
$s=[pscustomobject]@{Frames=@((Frame '2026-01-01T00:00:00Z' 0),(Frame '2026-01-01T00:00:01Z' 10),(Frame '2026-01-01T00:00:02Z' 99 'Error'),(Frame '2026-01-01T00:00:03Z' 20),(Frame 'invalid' 999),(Frame '2026-01-01T00:00:04Z' 30),(Frame '2026-01-01T00:00:04Z' 999),(Frame '2026-01-01T00:00:30Z' 40))}
$d=@(Get-PCSessionSensorDetails $s)[0]
$series=@(Get-PCSessionSensorSeries $s $d)
$p=Get-PCSessionPlot $series
Assert ($p.Samples -eq 5 -and $p.Maximum -eq 40 -and $p.Minimum -eq 0) 'Invalid readings plotted'
Assert (-not $p.Points[1].BreakBefore -and $p.Points[2].BreakBefore -and $p.Points[3].BreakBefore -and $p.Points[4].BreakBefore) 'Gap not preserved'
Assert ($p.Seconds -eq 30 -and $p.Points[1].X -lt 40) 'X scale ignored actual elapsed time'
$s=[pscustomobject]@{Frames=@((Frame '2026-01-01T00:00:00Z' 5))}
$p=Get-PCSessionPlot @(Get-PCSessionSensorSeries $s $d)
Assert ($p.Points.Count -eq 1 -and $p.Maximum -gt $p.Minimum) 'Single constant reading invisible'
Assert ($null -eq (Get-PCSessionPlot @())) 'Empty history invented a graph'
'PASS: timestamp scaling, missing/error/invalid/duplicate timestamp gaps, long gaps, zeros and constant single sample'
