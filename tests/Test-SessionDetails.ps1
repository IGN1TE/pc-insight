$ErrorActionPreference='Stop'
. "$PSScriptRoot/../SessionExport.ps1"
. "$PSScriptRoot/../SessionDetails.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Sensor($device,$value){[pscustomobject]@{Parent=$device;Identifier="$device/load/0";HardwareName=$device;Name='GPU Core';Type='Load';Value=$value}}
$session=[pscustomobject]@{Frames=@(
 [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 0),(Sensor '/gpu/0' 99),(Sensor '/gpu/1' 80));MemoryUsedPercent=40},
 [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 100),(Sensor '/gpu/1' 60));MemoryUsedPercent=60},
 [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 999));Issue='Sensor unavailable'},
 [pscustomobject]@{Sensors=@((Sensor '/gpu/0' $null))}
)}
$rows=@(Get-PCSessionSensorDetails $session)
$a=$rows|Where-Object Parent -eq '/gpu/0';$b=$rows|Where-Object Parent -eq '/gpu/1'
Assert ($a.Minimum -eq 0 -and $a.Maximum -eq 100 -and $a.Average -eq 50) 'Stats included duplicate or bad readings'
Assert ($a.Samples -eq 2 -and $a.RetainedFrames -eq 4) 'Wrong coverage denominator'
Assert ($b.Average -eq 70) 'Devices were merged'
Assert (($rows|Where-Object Parent -eq 'memory').Average -eq 50) 'Memory summary incorrect'
$head=[pscustomobject]@{Parent='/cpu/0';Identifier='/cpu/0/temp/0';Name='Distance to TjMax';Type='Temperature';Value=[double]::NaN}
$empty=@(Get-PCSessionSensorDetails ([pscustomobject]@{Frames=@([pscustomobject]@{Sensors=@($head)})}))[0]
Assert ($empty.MinText -eq 'Unavailable' -and $empty.Samples -eq 0) 'Non-finite reading included'
Assert ($empty.Type -eq 'Temperature headroom') 'Headroom mislabeled'
Assert (@(Get-PCSessionSensorDetails $null).Count -eq 0) 'Null session failed'
'PASS: separate devices, min/mean/max, zero, duplicate samples, issue exclusion, missing values, coverage, headroom and RAM'
