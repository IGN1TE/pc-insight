$ErrorActionPreference='Stop'
. "$PSScriptRoot/../ExtendedTests.ps1"
. "$PSScriptRoot/../Results.ps1"
function Assert($ok,$message) {if(-not $ok){throw $message}}
$f=[pscustomobject]@{QuerySeconds=0.1;CPUCelsius=40;Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Name='GPU Core';Type='Temperature';Value=45;HardwareName='NVIDIA GeForce RTX 5090'})}
Assert ((Find-PCGpuSensorName $f 'NVIDIA GeForce RTX 5090/PCIe/SSE2') -eq 'NVIDIA GeForce RTX 5090') 'Renderer should match GPU'
Assert ($null -eq (Find-PCGpuSensorName $f 'Intel UHD Graphics')) 'Mismatched GPU must not use another temperature'
Assert ($null -eq (Get-PCGpuStopReason $f 'NVIDIA GeForce RTX 5090')) 'Normal GPU should run'
$f.Sensors[0].Value=85
Assert ((Get-PCGpuStopReason $f 'NVIDIA GeForce RTX 5090') -match '85 C') 'GPU cutoff must stop'
Assert ((Get-PCGpuStopReason $f 'Other GPU') -match 'No temperature') 'Missing matched sensor must stop'
$a=[pscustomobject]@{Test='OpenGL-640x360-128shader-v1';Timestamp='2026-01-01';CPUName='CPU';Runtime='4';Workers=1;GpuFramesPerSecond=100;Renderer='GPU';DriverVersion='1';Completed=$true}
$b=$a.PSObject.Copy();$b.Timestamp='2026-01-02';$b.GpuFramesPerSecond=110
Assert ((Get-PCComparison $b @($a)) -match 'draws/s.*\+10.0%') 'GPU units or comparison wrong'
$b.DriverVersion='2'
Assert ($null -eq (Get-PCPreviousMatch $b @($a))) 'Different GPU driver must not auto-compare'
Add-Type -Path "$PSScriptRoot/../GpuWorkload.cs"
$pfd=[PCInsightGpuWorkload].GetNestedType('PFD',[Reflection.BindingFlags]::NonPublic)
Assert ([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($pfd)) -eq 40) 'Win32 pixel format descriptor size invalid'
Add-Type -Path "$PSScriptRoot/../MemoryWorkload.cs"
$m=[PCInsightMemoryWorkload]::new();$m.Start()
$wait=[Diagnostics.Stopwatch]::StartNew()
while(-not $m.Done -and $wait.Elapsed.TotalSeconds -lt 30){Start-Sleep -Milliseconds 100}
$m.Stop()
Assert (-not $m.Error -and $m.Seconds -ge 19.5 -and $m.CompletedMiB -gt 0) 'RAM workload did not complete bounded copy and verification'
$c=[PCInsightMemoryWorkload]::new();$c.Start();Start-Sleep -Milliseconds 100;$c.Stop()
Assert ($c.Done -and $c.Seconds -lt 5) 'RAM cancellation failed'
'PASS: GPU matching/cutoff, score compatibility, C# compilation, actual 20-second RAM workload and cancellation'
