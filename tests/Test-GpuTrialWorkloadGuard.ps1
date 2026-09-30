# Exercise the real ExtendedTests control flow with a tiny simulated workload.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../ExtendedTests.ps1"
. "$PSScriptRoot/../GpuOverclock.ps1"
. "$PSScriptRoot/../GpuClockTrial.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type @'
public class PCTrialMockWorkload {
 public bool Ready=true,Done=false,Stopped=false,Begun=false; public string Error=null,Renderer="Mock GPU/PCIe",Phase="Measuring";
 public double Seconds=30; public long Frames=3000;
 public void Prepare(double seconds) {} public void Begin(){Begun=true;} public void Stop(){Stopped=true;Done=true;}
}
'@
function New-PCGpuTestWorkload {$script:worker=[PCTrialMockWorkload]::new();$script:worker}
function Add-PCMemorySample($Frame){$Frame}
function Get-PCSensorFrame {
    [pscustomobject]@{QuerySeconds=0.1;CPUCelsius=40;Issue=$null;Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Name='GPU Core';Type='Temperature';Value=50;HardwareName='Mock GPU'})}
}
function Start-Sleep {param($Milliseconds)}
function Get-PCClockDevice($UUID){
    $script:clockChecks++
    $copy=$script:device|Select-Object *
    if($script:clockChecks -ge 3){$copy.TemperatureC=85}
    $copy
}
try{
    $failed=$false
    try{Invoke-PCExtendedTest -Kind gpu -ExpectedGpuName 'Other GPU'|Out-Null}catch{$failed=$true}
    Assert ($failed -and -not $script:worker.Begun -and $script:worker.Stopped) 'Wrong GPU began workload or leaked worker'
    $script:checks=0;$failed=$false
    try{
        Invoke-PCExtendedTest -Kind gpu -ExpectedGpuName 'Mock GPU' -Guard {
            $script:checks++
            if($script:checks -ge 3){throw 'Simulated clock/temperature failure during workload'}
        }|Out-Null
    }catch{$failed=$_.Exception.Message -like '*Simulated*'}
    Assert ($failed -and $script:worker.Begun -and $script:worker.Stopped) 'Guard failure did not stop a running workload'
    $script:device=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Driver='mock';Available=$true;CoreMHz=30;MemoryMHz=40;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
    $script:clockChecks=0;$failed=$false
    try{Invoke-PCClockTrialMeasurement $script:device '' 0 0|Out-Null}catch{$failed=$_.Exception.Message -match '85 C'}
    Assert ($failed -and $script:worker.Begun -and $script:worker.Stopped) 'Trial guard did not reach native-state validation or stop the real workload loop'
    $f=Get-PCSensorFrame
    foreach($value in @([double]::NaN,[double]::PositiveInfinity,0,-10)){
        $f.Sensors[0].Value=$value;Assert ($null -ne (Get-PCGpuStopReason $f 'Mock GPU')) 'Invalid GPU temperature accepted'
    }
    $f=Get-PCSensorFrame;$f.Issue='Sensor disconnected'
    Assert ($null -ne (Get-PCGpuStopReason $f 'Mock GPU')) 'Sensor error accepted'
    'PASS: real workload blocks wrong adapter before Begin and stops on live guard failures; invalid sensor readings rejected.'
}finally{if($script:worker){$script:worker.Stop()}}
