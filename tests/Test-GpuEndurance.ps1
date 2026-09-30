$ErrorActionPreference='Stop'
. "$PSScriptRoot/../ExtendedTests.ps1"
. "$PSScriptRoot/../GpuEndurance.ps1"
. "$PSScriptRoot/../Results.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Add-PCMemorySample($frame){$frame}
function Get-PCSensorFrame {
    $script:queries++
    $f=[pscustomobject]@{QuerySeconds=0.1;Issue=$null;CPUCelsius=55;Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Name='GPU Core';Type='Temperature';HardwareName='Test GPU';Value=65})}
    if($script:queries -ge 3){switch($script:mode){
        heat {$f.Sensors[0].Value=85}
        cpuheat {$f.CPUCelsius=85}
        missing {$f.Sensors=@()}
        invalid {$f.Sensors[0].Value=[double]::NaN}
        slow {$f.QuerySeconds=4}
        issue {$f.Issue='sensor failed'}
        exception {throw 'provider threw'}
    }}
    $f
}
function New-PCGpuEnduranceWorker {
    if($script:mode -eq 'init'){throw 'initialization failed'}
    $script:worker=[pscustomobject]@{Ready=$true;Done=$false;Error=$null;Renderer='Test GPU';Seconds=0.0;Frames=0L;Phase='Measuring';Stopped=$false;Renewals=0;Duration=0}
    $script:worker|Add-Member ScriptMethod PrepareMonitored {param($duration);$this.Duration=$duration}
    $script:worker|Add-Member ScriptMethod Begin {}
    $script:worker|Add-Member ScriptMethod KeepAlive {$this.Renewals++}
    $script:worker|Add-Member ScriptMethod Stop {$this.Stopped=$true;if($script:mode -eq 'stoperror'){throw 'stop failed'}}
    $script:worker
}
function Wait-PCGpuEnduranceTick {
    $script:worker.Seconds+=100;$script:worker.Frames+=1000
    if($script:mode -eq 'cancel'){Set-Content $script:stop 'stop'}
    if($script:mode -eq 'nativeerror'){$script:worker.Error='render failed';$script:worker.Done=$true}
    if($script:mode -eq 'early' -or $script:worker.Seconds -ge $script:worker.Duration){$script:worker.Done=$true}
}
$script:stop=Join-Path ([IO.Path]::GetTempPath()) ('pc-endurance-'+[guid]::NewGuid()+'.stop')
try{
 foreach($duration in 300,600){
  $script:mode='ok';$script:queries=0
  $r=@(Invoke-PCGpuEndurance $duration $script:stop|Where-Object Kind -eq Result)[0].Value
  Assert ($r.Completed -and $r.Seconds -eq $duration -and $r.PeakGPU -eq 65 -and $script:worker.Stopped) 'Completion/duration/peak/cleanup failed'
  Assert ($null -eq $r.GpuFramesPerSecond -and (Get-PCSessionSummary $r @()) -match 'Stability is not established') 'Endurance must not produce a benchmark or stability claim'
 }
 foreach($case in 'heat','cpuheat','missing','invalid','slow','issue','exception','cancel','init','early','nativeerror','stoperror'){
  $script:mode=$case;$script:queries=0;$script:worker=$null
  Remove-Item $script:stop -ErrorAction SilentlyContinue
  $r=@(Invoke-PCGpuEndurance 300 $script:stop|Where-Object Kind -eq Result)[0].Value
  Assert (-not $r.Completed -and $r.StopReason) "Failure reported as completed: $case"
  if($script:worker){Assert $script:worker.Stopped "Missing cleanup: $case"}
  if($case -in 'heat','cpuheat','missing','invalid','slow','issue','exception'){Assert ($script:worker.Renewals -eq 0) "Invalid query renewed heartbeat: $case"}
 }
 Set-Content $script:stop 'stop';$script:queries=0
 $r=@(Invoke-PCGpuEndurance 300 $script:stop|Where-Object Kind -eq Result)[0].Value
 Assert (-not $r.Completed -and $script:queries -eq 0) 'Pre-start cancellation failed'
 Add-Type -Path "$PSScriptRoot/../GpuWorkload.cs"
 $native=[PCInsightGpuWorkload]::new();$flags=[Reflection.BindingFlags]'NonPublic,Instance'
 $type=$native.GetType();$type.GetField('monitored',$flags).SetValue($native,$true)
 $type.GetField('heartbeat',$flags).SetValue($native,([Diagnostics.Stopwatch]::GetTimestamp()-7*[Diagnostics.Stopwatch]::Frequency))
 $expired=$false;try{$type.GetMethod('CheckHeartbeat',$flags).Invoke($native,@())}catch{$expired=$_.Exception.ToString() -match 'Sensor heartbeat expired'}
 Assert $expired 'Expired sensor heartbeat did not stop workload'
 $native.KeepAlive();$type.GetMethod('CheckHeartbeat',$flags).Invoke($native,@())
 foreach($duration in 31,[double]::NaN,[double]::PositiveInfinity){$rejected=$false;try{$native.Prepare($duration)}catch{$rejected=$true};Assert $rejected 'Short benchmark cap bypassed'}
 $rejected=$false;try{$native.PrepareMonitored(30)}catch{$rejected=$true};Assert $rejected 'Unsupported endurance duration accepted'
 'PASS: 300/600-second orchestration, cancellation, sensor/thermal/native failures, partial results, cleanup, heartbeat expiration/renewal and duration isolation (mocked hardware)'
}finally{Remove-Item $script:stop -ErrorAction SilentlyContinue}
