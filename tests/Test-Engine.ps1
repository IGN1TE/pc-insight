# Run with Windows PowerShell 5.1: powershell -NoProfile -File .\tests\Test-Engine.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\Engine.ps1"
. "$PSScriptRoot\..\Power.ps1"
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$s = [pscustomobject]@{ MemoryUsedPercent = 92; Disks = @([pscustomobject]@{ DeviceID='C:'; Size=100; FreeSpace=10 }); CPU=@([pscustomobject]@{ LoadPercentage=95 }); GPUTelemetry=@([pscustomobject]@{ Temperature='N/A' }) }
$text = (Get-PCInsights $s) -join "`n"
Assert ($text -match 'Memory use is 92') 'Memory pressure was not detected'
Assert ($text -match 'less than 15%') 'Low storage was not detected'
Assert ($text -notmatch 'GPU temperature is at least') 'Unknown GPU temperature must not become a reading'
$s.MemoryUsedPercent = $null; $s.Disks = @(); $s.CPU = @(); $s.GPUTelemetry = @()
Assert (((Get-PCInsights $s) -join "`n") -notmatch '\[HIGH') 'Missing readings generated a high-severity finding'
# Mock powercfg: no system settings are modified by these tests.
$script:active = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:target = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:deny = $false
function Invoke-PowerCfg([string[]]$Arguments) {
    switch ($Arguments[0]) {
        '/list' { "Power Scheme GUID: $script:active (Current)`nPower Scheme GUID: $script:target (Target)" }
        '/getactivescheme' { "Power Scheme GUID: $script:active (Current)" }
        '/setactive' { if (-not $script:deny) { $script:active = $Arguments[1] } }
    }
}
Set-VerifiedPlan $script:target
Assert ((Get-ActivePlan) -eq $script:target) 'Applied plan was not verified'
$script:deny = $true; $script:target = '381b4222-f694-41f0-9685-ff5bb260df2e'
$rejected = $false
try { Set-VerifiedPlan $script:target } catch { $rejected = $true }
Assert $rejected 'Unsuccessful plan changes must fail verification'
$rejected = $false
try { Set-VerifiedPlan 'garbage' } catch { $rejected = $true }
Assert $rejected 'Invalid IDs must be rejected'
'PASS: insight thresholds, missing sensors, plan verification and invalid IDs'
. "$PSScriptRoot\..\Monitor.ps1"
$f = [pscustomobject]@{ Issue=$null; CPUCelsius=50; QuerySeconds=0.1 }
Assert ($null -eq (Get-PCStopReason $f)) 'Normal sensor frame incorrectly blocks the test'
$f.CPUCelsius = 85
Assert ((Get-PCStopReason $f) -match '85 C') 'Cutoff boundary must stop the test'
$f.CPUCelsius = $null
Assert ((Get-PCStopReason $f) -match 'No valid') 'Missing temperature must stop the test'
$f.CPUCelsius = 50; $f.QuerySeconds = 3.1
Assert ((Get-PCStopReason $f) -match 'response limit') 'Slow sensors must stop the test'
$f.QuerySeconds = 0.1; $f.Issue = 'Provider exited'
Assert ((Get-PCStopReason $f) -match 'unavailable') 'Provider failure must stop the test'
$rows = @(
    [pscustomobject]@{ Name='CPU'; SensorType='Temperature'; Value=45; Identifier='/intelcpu/0/temperature/0'; Parent='/intelcpu/0' },
    [pscustomobject]@{ Name='Missing'; SensorType='Temperature'; Value=$null },
    [pscustomobject]@{ Name='Invalid'; SensorType='Temperature'; Value=[double]::NaN }
)
$clean = @(Convert-PCSensorRows $rows)
Assert ($clean.Count -eq 1 -and $clean[0].Value -eq 45) 'Null and NaN readings must be excluded'
# Brief, single-worker execution verifies compilation, bounded duration and cancellation.
Initialize-PCWorkers
$worker = [PCInsightWorkload]::new()
$worker.Start(1, 0.2)
Start-Sleep -Milliseconds 400
Assert $worker.Done 'Worker did not obey its independent deadline'
$worker.Stop()
Assert ($worker.CompletedMiB -gt 0 -and -not $worker.Error) 'Workload did not produce a valid result'
$worker2 = [PCInsightWorkload]::new(); $worker2.Start(1, 20); $worker2.Stop()
Assert $worker2.Done 'Worker did not stop after cancellation'
'PASS: sensor cutoff, missing/invalid readings, provider failure, workload deadline and cancellation'
