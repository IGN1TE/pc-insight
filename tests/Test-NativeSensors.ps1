$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\NativeSensors.ps1"
. "$PSScriptRoot\..\Monitor.ps1"
function Assert($ok,$message) { if (-not $ok) { throw $message } }
$hw = [pscustomobject]@{
    Identifier='/intelcpu/0'; SubHardware=@(); Sensors=@(
        [pscustomobject]@{ Name='CPU Package'; SensorType='Temperature'; Value=32; Identifier='/intelcpu/0/temperature/0' },
        [pscustomobject]@{ Name='Distance to TjMax'; SensorType='Temperature'; Value=76; Identifier='/intelcpu/0/temperature/1' },
        [pscustomobject]@{ Name='Clock'; SensorType='Clock'; Value=5300; Identifier='/intelcpu/0/clock/0' },
        [pscustomobject]@{ Name='Missing'; SensorType='Temperature'; Value=$null; Identifier='/intelcpu/0/temperature/2' }
    )
}
$hw | Add-Member ScriptMethod Update { $script:updates++ }
$script:updates = 0
$script:NativeComputer = [pscustomobject]@{Hardware=@($hw)}
$script:NativeComputer | Add-Member ScriptMethod Close { $script:closed=$true }
$f = Get-PCNativeFrame
Assert ($f.CPUCelsius -eq 32 -and $null -eq $f.Issue) 'Incorrect actual temperature'
Assert ($script:updates -eq 1) 'Hardware was not updated'
Assert ($f.Sensors.Count -eq 3) 'Missing value was retained'
$hw.Sensors[0].Value=86
Assert ((Get-PCStopReason (Get-PCNativeFrame)) -match '85 C') 'Thermal stop failed'
$hw.Sensors[0].Value=$null
Assert ((Get-PCStopReason (Get-PCNativeFrame)) -match 'unavailable') 'Missing temperature must block workload'
Close-PCNativeSensors
Assert ($script:closed -and $null -eq $script:NativeComputer) 'Hardware cleanup failed'
# Inspect the real bundled binary API without opening hardware.
$vendor=Join-Path $PSScriptRoot '..\vendor\LibreHardwareMonitor'
foreach($entry in (Get-Content (Join-Path $vendor 'hashes.json') -Raw | ConvertFrom-Json)) {
    Assert ((Get-FileHash (Join-Path $vendor $entry.Name)).Hash -eq $entry.SHA256) 'Vendor file hash mismatch'
}
$a=[Reflection.Assembly]::LoadFrom((Join-Path $vendor 'LibreHardwareMonitorLib.dll'))
$t=$a.GetType('LibreHardwareMonitor.Hardware.Computer',$true)
Assert ($null -ne $t.GetProperty('IsCpuEnabled') -and $null -ne $t.GetProperty('IsGpuEnabled')) 'Library enable flags unavailable'
Assert ($null -ne $t.GetMethod('Open') -and $null -ne $t.GetMethod('Close')) 'Library lifecycle methods unavailable'
'PASS: direct update, actual-temperature filtering, missing readings, cutoff, cleanup, bundled hashes and real library API'
