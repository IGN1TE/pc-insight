# Continuous workload observation, deliberately separate from comparable benchmark scores.
function New-PCGpuEnduranceWorker {
    if(-not ('PCInsightGpuWorkload' -as [type])){Add-Type -Path "$PSScriptRoot\GpuWorkload.cs"}
    [PCInsightGpuWorkload]::new()
}
function Wait-PCGpuEnduranceTick {Start-Sleep -Milliseconds 1000}
function Get-PCGpuEnduranceGuard($Frame,[string]$Name){
    if($Frame.Issue){return 'Sensor provider reported an error: '+$Frame.Issue}
    if($null -eq $Frame.QuerySeconds -or [double]::IsNaN([double]$Frame.QuerySeconds) -or [double]::IsInfinity([double]$Frame.QuerySeconds) -or $Frame.QuerySeconds -lt 0){return 'Sensor query timing is unavailable or invalid.'}
    $temps=@($Frame.Sensors|Where-Object { $_.Parent -match '^/gpu' -and $_.Name -eq 'GPU Core' -and $_.Type -eq 'Temperature' -and $_.HardwareName -eq $Name })
    if(-not $temps.Count){return 'No temperature reading for the selected OpenGL GPU.'}
    foreach($t in $temps){if($null -eq $t.Value -or [double]::IsNaN([double]$t.Value) -or [double]::IsInfinity([double]$t.Value) -or $t.Value -le 0 -or $t.Value -gt 125){return 'GPU temperature reading is invalid.'}}
    Get-PCGpuStopReason $Frame $Name
}
function Invoke-PCGpuEndurance([ValidateSet(300,600)][int]$DurationSeconds,[string]$StopPath){
    $frames=[Collections.Generic.List[object]]::new();$worker=$null;$reason=$null;$gpuName=$null;$seconds=0.0;$renderer=$null;$peakGPU=$null;$lastDraws=0L
    $watch=[Diagnostics.Stopwatch]::StartNew();$progressWatch=[Diagnostics.Stopwatch]::StartNew()
    try{
        if(Test-Path -LiteralPath $StopPath){throw 'Cancelled before starting.'}
        $first=Add-PCMemorySample (Get-PCSensorFrame);$frames.Add($first)
        [pscustomobject]@{Kind='Frame';Value=$first}
        $worker=New-PCGpuEnduranceWorker;$worker.PrepareMonitored($DurationSeconds)
        while(-not $worker.Ready -and -not $worker.Done -and $watch.Elapsed.TotalSeconds -lt 15){
            if(Test-Path -LiteralPath $StopPath){throw 'Cancelled during GPU initialization.'};Start-Sleep -Milliseconds 100
        }
        if($worker.Error){throw $worker.Error};if(-not $worker.Ready){throw 'GPU initialization timed out.'}
        $renderer=$worker.Renderer;$gpuName=Find-PCGpuSensorName $first $renderer
        if(-not $gpuName){throw 'Cannot match the OpenGL renderer to a GPU temperature sensor.'}
        $fresh=Add-PCMemorySample (Get-PCSensorFrame);$frames.Add($fresh)
        $guard=Get-PCGpuEnduranceGuard $fresh $gpuName;if($guard){throw $guard}
        if(Test-Path -LiteralPath $StopPath){throw 'Cancelled before GPU load.'}
        $worker.Begin();$watch.Restart();$progressWatch.Restart()
        while(-not $worker.Done -and $watch.Elapsed.TotalSeconds -lt ($DurationSeconds+20)){
            if(Test-Path -LiteralPath $StopPath){$reason='Cancelled by user.';break}
            Wait-PCGpuEnduranceTick
            if(Test-Path -LiteralPath $StopPath){$reason='Cancelled by user.';break}
            $frame=Add-PCMemorySample (Get-PCSensorFrame);$frames.Add($frame)
            [pscustomobject]@{Kind='Frame';Value=$frame}
            $guard=Get-PCGpuEnduranceGuard $frame $gpuName;if($guard){$reason=$guard;break}
            # Renew only after a successful fresh sensor query. Native lease expires after six seconds.
            $worker.KeepAlive()
            if($worker.Frames -gt $lastDraws){$lastDraws=$worker.Frames;$progressWatch.Restart()}
            elseif($worker.Phase -ne 'Warm-up (unscored)' -and $progressWatch.Elapsed.TotalSeconds -gt 10){$reason='GPU workload stopped making progress.';break}
            $seconds=[math]::Max(0,[double]$worker.Seconds)
            [pscustomobject]@{Kind='Progress';Value=[math]::Min(100,100*$seconds/$DurationSeconds)}
            [pscustomobject]@{Kind='EnduranceProgress';Value=('{0} / {1} seconds measured · {2} · Stop saves a partial result' -f [int]$seconds,$DurationSeconds,$worker.Phase)}
            if($frames.Count -gt 650){$reason='Sensor sample limit reached.';break}
        }
        if($worker.Error){$reason=$worker.Error}
        if(-not $reason -and -not $worker.Done){$reason='GPU workload exceeded its response deadline.'}
    }catch{$reason=$_.Exception.Message}
    finally{
        if($worker){try{$worker.Stop()}catch{$reason='GPU stop could not be confirmed: '+$_.Exception.Message};$seconds=[double]$worker.Seconds}
    }
    if(-not $reason -and ($seconds -lt $DurationSeconds-0.5 -or -not $worker -or $worker.Frames -le 0)){$reason='GPU workload ended before the requested interval completed.'}
    $valid=@($frames|Where-Object {-not $_.Issue}|ForEach-Object {$_.Sensors}|Where-Object {$_.Parent -match '^/gpu' -and $_.Name -eq 'GPU Core' -and $_.Type -eq 'Temperature' -and $_.HardwareName -eq $gpuName -and $null -ne $_.Value -and $_.Value -gt 0 -and $_.Value -le 125})
    if($valid.Count){$peakGPU=($valid|Measure-Object Value -Maximum).Maximum}
    $outcome=if($reason){'Stopped: '+$reason}else{'Completed without detected workload errors. Stability is not established.'}
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{
        Test="GPU-endurance-${DurationSeconds}s-v1";Timestamp=(Get-Date).ToString('o');RequestedSeconds=$DurationSeconds;Seconds=$seconds;WarmupSeconds=5;Workers=1;Runtime=[Environment]::Version.ToString()
        Completed=($null -eq $reason);StopReason=$reason;EnduranceOutcome=$outcome;PeakGPU=$peakGPU;GPUName=$gpuName;Renderer=$renderer
        MiBPerSecond=$null;GpuFramesPerSecond=$null;PeakCPU=($frames|Where-Object {$null -ne $_.CPUCelsius}|Measure-Object CPUCelsius -Maximum).Maximum;Frames=@($frames.ToArray())
        Limitations='Continuous offscreen OpenGL shader load; five-second warm-up plus requested measured interval. Observes API errors, missing/slow sensors and sampled 85 C CPU/GPU cutoff. No pixel-correctness, VRAM integrity, game, WHEA or driver-reset-log validation. A driver hang can delay stopping; heartbeat checks run between draw batches. No clock writes or automatic restoration: use Tuning to restore saved offsets. Completion is not proof of stability; no comparable benchmark score.'
    }}
}
