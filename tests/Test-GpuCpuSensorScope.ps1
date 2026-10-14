$ErrorActionPreference='Stop'
foreach($m in 'NativeSensors','Monitor','ExtendedTests','Power','Results','RepeatedTests','Tuning','SessionExport','SessionDetails','GuidedOptimize','GpuOverclock','GuidedClocks'){. "$PSScriptRoot/../$m.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Assert $failed $message}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-sensor-scope-'+[guid]::NewGuid());$null=New-Item -ItemType Directory $dir
$j=Join-Path $dir 'clock.json';$p=Join-Path $dir 'guide.json'
$gpu=[pscustomobject]@{Name='Mock GPU';Identifier='/gpu-nvidia/0';SubHardware=@();Sensors=@([pscustomobject]@{Name='GPU Core';SensorType='Temperature';Value=50;Identifier='/gpu-nvidia/0/temperature/0'})}
$gpu|Add-Member ScriptMethod Update {if($script:providerFails){throw 'Mock provider failed'}}
$script:NativeComputer=[pscustomobject]@{Hardware=@($gpu)}
function Get-ActivePlan {'plan-a'}
function Get-PCClockDevice($UUID){[pscustomobject]@{UUID='GPU-abcd';Name='Mock GPU';Driver='1';Available=$true;CoreMHz=0;MemoryMHz=0;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}}
function Get-PCDeviceById($UUID){[pscustomobject]@{UUID='GPU-abcd';Name='Mock GPU';Driver='1';Current=600;Min=400;Max=600;Available=$true}}
function Set-PCClockOffset {throw 'No hardware write is permitted in this baseline test'}
try {
 $frame=Get-PCNativeFrame
 Assert ($null -eq $frame.Issue -and $frame.CPUWarning -and $null -eq $frame.CPUCelsius) 'Missing CPU temperature was not scoped as a CPU warning'
 Assert ((Get-PCStopReason $frame) -match 'CPU temperature unavailable') 'CPU/RAM load must remain blocked without CPU temperature'
 Assert ($null -eq (Get-PCGpuStopReason $frame 'Mock GPU')) 'Valid matched GPU readings were blocked by CPU-only warning'
 $g=New-PCClockGuide (Get-PCClockDevice '') (Get-PCDeviceById '') 'plan-a' $j;Enable-PCGpuAutoScan $g
 $rows=@(1..3|ForEach-Object{
  $state=[pscustomobject]@{Devices=@((Get-PCDeviceById ''));Issue=$null;ClockIssue=$null;ClockOffsets=@((Get-PCClockDevice ''))}
  [pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';BatchId='baseline';RunIndex=$_;Completed=$true;StopReason=$null;Timestamp="baseline-$_";Seconds=30;GPUName='Mock GPU';Renderer='Mock GPU';CPUName='Mock CPU';Runtime='4';Workers=1;DriverVersion='1';MemoryConfig='RAM';Plan='plan-a';GpuFramesPerSecond=100;PowerStateAtStart=$state;PowerStateAtEnd=$state;Frames=@($frame)}
 })
 Complete-PCGpuAutoScanBatch $g $rows $j $p
 Assert ($g.Phase -eq 'Review' -and $g.Summary -match 'CPU temperatures were unavailable' -and -not (Test-Path $j)) 'GPU baseline did not reach review with honest CPU coverage'
 $summary=Get-PCSessionSummary $rows[0] @()
 Assert ($summary -match 'Peak GPU core temperature: 50' -and $summary -match 'CPU temperature warning:') 'Saved summary hid valid GPU evidence or CPU warning'
 $details=@(Get-PCSessionSensorDetails $rows[0])
 Assert ($details.Count -eq 1 -and $details[0].Maximum -eq 50) 'CPU warning discarded GPU sensor statistics'
 $frame.Issue='Mock provider failed'
 Assert ((Get-PCGpuStopReason $frame 'Mock GPU') -match 'Mock provider failed') 'Real provider error was ignored'
 Reject {Assert-PCGuideBatch $g $rows 600} 'Real provider error accepted by guided tuning'
 $frame.Issue=$null;$frame.QuerySeconds=4
 Assert ((Get-PCGpuStopReason $frame 'Mock GPU') -match '3 seconds') 'Slow query accepted'
 $frame.QuerySeconds=0.1;$frame.Sensors[0].Value=85
 Assert ((Get-PCGpuStopReason $frame 'Mock GPU') -match '85 C') 'GPU thermal cutoff lost'
 $frame.Sensors[0].Value=50;$frame.CPUCelsius=85
 Assert ((Get-PCGpuStopReason $frame 'Mock GPU') -match 'CPU reached') 'Available CPU thermal cutoff lost'
 $frame.CPUCelsius=$null;$frame.Sensors=@()
 Assert ((Get-PCGpuStopReason $frame 'Mock GPU') -match 'No temperature') 'Missing GPU temperature accepted'
 Reject {Assert-PCGpuScanBatch $g $rows} 'Missing GPU evidence accepted by scanner'
 $script:providerFails=$true;$failedFrame=Get-PCNativeFrame
 Assert ($failedFrame.Issue -match 'Mock provider failed' -and -not $failedFrame.CPUWarning) 'Provider exception was mislabeled as a harmless CPU warning'
 'PASS: native CPU-only warning, GPU baseline review, CPU/RAM blocking, visible coverage, GPU statistics and preserved provider/temperature/query guards'
}finally{Remove-Item $dir -Recurse -Force}
