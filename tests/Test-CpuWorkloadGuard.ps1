# Exercise real Monitor control flow with a simulated CPU worker. No real load or sensors.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Monitor.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type @'
public class PCInsightWorkload {
 public static PCInsightWorkload Last; public bool Stopped=false,Done=false; public string Error=null;
 public double Seconds=60; public long CompletedMiB=6000;
 public PCInsightWorkload(){Last=this;} public void Start(int count,double seconds){} public void Stop(){Stopped=true;Done=true;}
}
'@
function Get-PCSensorFrame {[pscustomobject]@{CPUCelsius=50;QuerySeconds=0.1;Issue=$null}}
function Start-Sleep {param($Milliseconds)}
$checks=0;$failed=$false
try{Invoke-PCSensorSession -WithLoad -DurationSeconds 60 -Guard {$script:checks++;if($script:checks -eq 3){throw 'Cancelled'}}|Out-Null}catch{$failed=$_.Exception.Message -eq 'Cancelled'}
Assert ($failed -and [PCInsightWorkload]::Last.Stopped) 'Cancellation did not stop the active CPU worker'
foreach($key in 'CPUCelsius','QuerySeconds'){
    foreach($value in @($null,[double]::NaN,[double]::PositiveInfinity,-1,$true,'bad')){
        $f=Get-PCSensorFrame;$f.$key=$value
        Assert ($null -ne (Get-PCStopReason $f)) "Invalid $key accepted"
    }
}
$f=Get-PCSensorFrame;$f.CPUCelsius=85;Assert ((Get-PCStopReason $f) -match '85 C') 'Cutoff boundary failed'
$f=Get-PCSensorFrame;$f.QuerySeconds=3.1;Assert ($null -ne (Get-PCStopReason $f)) 'Slow query accepted'
$f=Get-PCSensorFrame;$f.QuerySeconds=0;Assert ($null -eq (Get-PCStopReason $f)) 'Zero query duration rejected'
'PASS: CPU workload cancellation releases worker; invalid, missing, nonfinite, hot and slow sensor readings stop measurement.'
