# Recorded data only: no device, sensor, workload or hardware-setting calls.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GpuOverclock.ps1"
. "$PSScriptRoot/../GpuClockTrial.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Copy-Value($value){$value|ConvertTo-Json -Depth 12|ConvertFrom-Json}
function Sensor($Name,$Type,$Value,$Id,$Parent='/gpu-nvidia/0',$GPU='Mock GPU'){
    [pscustomobject]@{Name=$Name;Type=$Type;Value=$Value;Identifier=$Id;Parent=$Parent;HardwareName=$GPU}
}
function Frame([int]$Second,$Sensors,$Issue=''){
    [pscustomobject]@{Timestamp=([datetimeoffset]'2026-01-01T12:00:00Z').AddSeconds($Second).ToString('o');QuerySeconds=0.1;Issue=$Issue;Sensors=@($Sensors)}
}
function Result($Frames){[pscustomobject]@{GPUName='Mock GPU';Frames=@($Frames)}}
function Run($Telemetry){[pscustomobject]@{GPUName='Mock GPU';Telemetry=$Telemetry;RunIndex=1;Eligible=$true}}
function Get-PCClockDevice {throw 'Telemetry queried hardware'}
function Get-PCSensorFrame {throw 'Telemetry queried sensors'}
function Set-PCClockOffset {throw 'Telemetry wrote hardware'}
$cpu=Sensor 'CPU Package' 'Temperature' 95 '/cpu/temp' '/intelcpu/0' 'Mock CPU'
$other=Sensor 'GPU Core' 'Temperature' 99 '/other/temp' '/gpu-amd/0' 'Other GPU'
$frames=@(0..4|ForEach-Object {
    Frame $_ @((Sensor 'GPU Core' 'Temperature' (50+$_) '/gpu/temperature/0'),(Sensor 'GPU Core' 'Clock' (2000+10*$_) '/gpu/clock/0'),(Sensor 'GPU Package' 'Power' (100+$_) '/gpu/power/0'),(Sensor 'GPU Core' 'Load' 0 '/gpu/load/0'),$cpu,$other)
})
$source=Result $frames;$t=ConvertTo-PCClockTrialTelemetry $source;$run=Run $t
Assert ($t.Channels.Count -eq 4 -and $t.Samples.Count -eq 5 -and -not $t.Truncated) 'GPU channel capture or bounds incorrect'
$channels=@(Get-PCClockTrialTelemetryChannels $run)
$temp=@($channels|Where-Object Type -eq 'Temperature')[0];$clock=@($channels|Where-Object Type -eq 'Clock')[0];$load=@($channels|Where-Object Type -eq 'Load')[0]
$v=Get-PCClockTrialTelemetryView $run $temp
Assert ($v.Plot.Samples -eq 5 -and $v.Plot.Seconds -eq 4 -and $v.Plot.Points[-1].Value -eq 54) 'Temperature timeline or elapsed time incorrect'
Assert ((Get-PCClockTrialTelemetryView $run $clock).Plot.Points[0].Value -eq 2000) 'Clock was confused with the equally named temperature sensor'
Assert ((Get-PCClockTrialTelemetryView $run $load).Plot.Samples -eq 5) 'Zero load was treated as missing'
$frames[0].Sensors[0].Value=999
Assert ((Get-PCClockTrialTelemetryView $run $temp).Plot.Points[0].Value -eq 50) 'Telemetry shares mutable source readings'
$badFrames=@(
    (Frame 0 @((Sensor 'GPU Core' 'Temperature' 50 '/gpu/temperature/0'))),
    (Frame 1 @((Sensor 'GPU Core' 'Temperature' 51 '/gpu/temperature/0')) 'query error'),
    (Frame 2 @()),
    (Frame 3 @((Sensor 'GPU Core' 'Temperature' 53 '/gpu/temperature/0'),(Sensor 'GPU Core' 'Temperature' 99 '/gpu/temperature/0'))),
    (Frame 4 @((Sensor 'GPU Core' 'Temperature' ([double]::NaN) '/gpu/temperature/0'))),
    (Frame 5 @((Sensor 'GPU Core' 'Temperature' 55 '/gpu/temperature/0'))),
    (Frame 5 @((Sensor 'GPU Core' 'Temperature' 56 '/gpu/temperature/0'))),
    (Frame 4 @((Sensor 'GPU Core' 'Temperature' 57 '/gpu/temperature/0'))),
    (Frame 8 @((Sensor 'GPU Core' 'Temperature' 58 '/gpu/temperature/0'))),
    (Frame 9 @((Sensor 'GPU Core' 'Temperature' 59 '/gpu/temperature/0'))),
    (Frame 20 @((Sensor 'GPU Core' 'Temperature' 60 '/gpu/temperature/0')))
)
$badFrames[8].Timestamp='not a timestamp';$badFrames[9].QuerySeconds=3.1
$bad=Run (ConvertTo-PCClockTrialTelemetry (Result $badFrames));$ch=@(Get-PCClockTrialTelemetryChannels $bad)[0];$v=Get-PCClockTrialTelemetryView $bad $ch
Assert ($v.Plot.Samples -eq 3 -and $v.Plot.RetainedFrames -eq 11 -and $v.Plot.Points[1].BreakBefore -and $v.Plot.Points[2].BreakBefore) 'Missing, duplicate, invalid, failed/slow query or unordered readings were connected'
$roundtrip=Copy-Value $bad
Assert ((Get-PCClockTrialTelemetryView $roundtrip $ch).Plot.Samples -eq 3 -and @($roundtrip.Telemetry.Samples[2].Values).Count -eq 1 -and $null -eq $roundtrip.Telemetry.Samples[2].Values[0]) 'JSON round-trip lost explicit missing values'
$mixed=ConvertTo-PCClockTrialTelemetry (Result @((Frame 0 @((Sensor 'GPU Core' 'Temperature' 50 '/a' '/gpu-nvidia/0'),(Sensor 'GPU Core' 'Temperature' 51 '/b' '/gpu-nvidia/1')))))
Assert ($mixed.Channels.Count -eq 0 -and ($mixed.Notes -join ' ') -match 'Multiple sensor devices') 'Identically named GPUs were combined'
$extreme=Copy-Value $run;$extreme.Telemetry.Samples[0].Values[$temp.Index]=[double]::PositiveInfinity
Assert ((Get-PCClockTrialTelemetryView $extreme $temp).Plot.Samples -eq 4) 'Imported nonfinite value was plotted'
$extreme.Telemetry.Channels[$temp.Index].HardwareName='Other GPU'
Assert (-not (Get-PCClockTrialTelemetryView $extreme $temp).Plot) 'Tampered channel identity was accepted'
$malformed=Copy-Value $run;$malformed.Telemetry.Samples[0].Values=@(999)
Assert ((Get-PCClockTrialTelemetryView $malformed $temp).Plot.Samples -eq 4) 'Mismatched vector shifted sensor readings'
$malformed.Telemetry.Samples[0].Values='50'
Assert ((Get-PCClockTrialTelemetryView $malformed $temp).Plot.Samples -eq 4) 'Scalar values were interpreted as an indexed sensor vector'
Assert ($null -eq (ConvertTo-PCTrialSensorValue $true 'Clock')) 'Boolean reading was treated as a clock'
$headroom=Run (ConvertTo-PCClockTrialTelemetry (Result @((Frame 0 @((Sensor 'GPU Temperature Headroom' 'Temperature' 30 '/gpu/headroom'))))))
Assert (@(Get-PCClockTrialTelemetryChannels $headroom)[0].Label -match 'Temperature headroom') 'Headroom was shown as an absolute temperature'
$constant=Get-PCClockTrialTelemetryView $run $load
Assert ($constant.Plot.Minimum -lt $constant.Plot.Maximum -and $constant.Plot.Points[0].BreakBefore) 'Constant values were not plotted'
$single=Run (ConvertTo-PCClockTrialTelemetry (Result @($source.Frames[1])))
Assert ((Get-PCClockTrialTelemetryView $single @(Get-PCClockTrialTelemetryChannels $single)[0]).Plot.Samples -eq 1) 'One sample was hidden'
$huge=Result @(0..69|ForEach-Object {Frame $_ @(0..19|ForEach-Object {Sensor ('Channel '+$_) 'Clock' $_ ('/gpu/clock/'+$_)})})
$bounded=ConvertTo-PCClockTrialTelemetry $huge
Assert ($bounded.Samples.Count -eq 64 -and $bounded.Channels.Count -eq 16 -and $bounded.SourceFrames -eq 70 -and $bounded.Truncated) 'Telemetry retention is unbounded or silently truncated'
$report=[pscustomobject]@{Schema=2;BeforeRuns=@((Run $bounded),(Run $bounded),(Run $bounded));AfterRuns=@((Run $bounded),(Run $bounded),(Run $bounded))}
Assert (@(Get-PCClockTrialTelemetryRuns $report).Count -eq 6) 'Per-run picker lost measurements'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-telemetry-'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $dir
try{
    $path=Join-Path $dir 'report.json';Save-PCClockJournal $report $path
    $saved=Get-Content $path -Raw|ConvertFrom-Json
    Assert ($saved.AfterRuns[2].Telemetry.Samples[63].Values[15] -is [ValueType] -and (Get-Item $path).Length -lt 1048576) 'Persisted vectors were truncated or exceeded archive size limit'
}finally{Remove-Item $dir -Recurse -Force}
Assert (@(Get-PCClockTrialTelemetryChannels ([pscustomobject]@{GPUName='Mock GPU'})).Count -eq 0) 'Legacy run fabricated telemetry'
'PASS: bounded GPU-only telemetry, exact sensor identity, zero/missing/duplicate values, query failures, timestamp gaps, legacy records, headroom labels and full JSON persistence.'
