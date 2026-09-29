function Get-PCGpuStopReason($frame, [string]$HardwareName) {
    if ($frame.QuerySeconds -gt 3) { return 'Sensor query exceeded 3 seconds.' }
    $temps = @($frame.Sensors | Where-Object { $_.Parent -match '^/gpu' -and $_.Name -eq 'GPU Core' -and $_.Type -eq 'Temperature' -and $_.HardwareName -eq $HardwareName -and $null -ne $_.Value })
    if (-not $temps.Count) { return 'No temperature reading for the selected OpenGL GPU.' }
    if (($temps | Measure-Object Value -Maximum).Maximum -ge 85) { return 'GPU core reached the 85 C preview cutoff.' }
    if ($null -ne $frame.CPUCelsius -and $frame.CPUCelsius -ge 85) { return 'CPU reached the 85 C preview cutoff.' }
    return $null
}
function Find-PCGpuSensorName($frame,[string]$Renderer) {
    foreach ($sensor in $frame.Sensors) {
        if ($sensor.Parent -notmatch '^/gpu' -or $sensor.Type -ne 'Temperature' -or $sensor.Name -ne 'GPU Core' -or -not $sensor.HardwareName) { continue }
        $name = ([string]$sensor.HardwareName).Trim()
        if ($Renderer.StartsWith($name,[StringComparison]::OrdinalIgnoreCase)) { return $name }
    }
    return $null
}
function Invoke-PCExtendedTest([ValidateSet('memory','gpu')][string]$Kind) {
    $rates = [Collections.Generic.List[object]]::new(); $previousSeconds=0.0; $previousFrames=0L
    $frames = [Collections.Generic.List[object]]::new();$worker=$null;$reason=$null;$rate=$null;$gpuRate=$null;$gpuName=$null
    $first=Add-PCMemorySample (Get-PCSensorFrame);$frames.Add($first)
    [pscustomobject]@{Kind='Frame';Value=$first}
    if ($Kind -eq 'memory') {
        $reason=Get-PCStopReason $first
        if($reason){throw "RAM test was not started: $reason"}
        $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop
        if ([double]$os.FreePhysicalMemory -lt 786432) { throw 'RAM test needs at least 768 MiB of free physical memory.' }
        if (-not ('PCInsightMemoryWorkload' -as [type])) { Add-Type -Path "$PSScriptRoot\MemoryWorkload.cs" }
        $worker=[PCInsightMemoryWorkload]::new()
    } else {
        if (-not ('PCInsightGpuWorkload' -as [type])) { Add-Type -Path "$PSScriptRoot\GpuWorkload.cs" }
        $worker=[PCInsightGpuWorkload]::new()
    }
    try {
        if ($Kind -eq 'gpu') {
            $worker.Prepare(30);$init=[Diagnostics.Stopwatch]::StartNew()
            while (-not $worker.Ready -and -not $worker.Done -and $init.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 100 }
            if ($worker.Error) { throw $worker.Error }
            if (-not $worker.Ready) { throw 'GPU initialization timed out.' }
            $gpuName=Find-PCGpuSensorName $first $worker.Renderer
            if (-not $gpuName) { throw "GPU test unavailable: cannot match renderer '$($worker.Renderer)' to a GPU temperature sensor." }
            $fresh=Get-PCSensorFrame
            $reason=Get-PCGpuStopReason $fresh $gpuName
            if($reason){throw "GPU test was not started: $reason"}
            $worker.Begin()
        } else { $worker.Start() }
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while (-not $worker.Done -and $watch.Elapsed.TotalSeconds -lt 45) {
            Start-Sleep -Milliseconds 1000
            $frame=Add-PCMemorySample (Get-PCSensorFrame);$frames.Add($frame)
            [pscustomobject]@{Kind='Frame';Value=$frame}
            $duration=20; if($Kind -eq 'gpu'){$duration=30}
            [pscustomobject]@{Kind='Progress';Value=[math]::Min(100,100*$worker.Seconds/$duration)}
            if($Kind -eq 'gpu'){
                [pscustomobject]@{Kind='Phase';Value=$worker.Phase}
                $elapsed=$worker.Seconds; $draws=$worker.Frames
                if($elapsed-$previousSeconds -ge 0.5){
                    $rates.Add([pscustomobject]@{ElapsedSeconds=$elapsed;DrawsPerSecond=($draws-$previousFrames)/($elapsed-$previousSeconds)})
                    $previousSeconds=$elapsed;$previousFrames=$draws
                }
            }
            $reason=if($Kind -eq 'gpu'){Get-PCGpuStopReason $frame $gpuName}else{Get-PCStopReason $frame}
            if($reason){break}
        }
        if (-not $reason -and -not $worker.Done) { $reason='Workload exceeded its response deadline.' }
        if ($worker.Error) { $reason=$worker.Error }
    } finally { if($worker){$worker.Stop()} }
    $minimum=19.5; if($Kind -eq 'gpu'){$minimum=29.5}
    if (-not $reason -and $worker.Seconds -ge $minimum) {
        if($Kind -eq 'gpu'){$gpuRate=[math]::Round($worker.Frames/$worker.Seconds,2)}else{$rate=[math]::Round($worker.CompletedMiB/$worker.Seconds,2)}
    } elseif (-not $reason) { $reason='Workload ended before the measurement interval completed.' }
    $peak=($frames | Where-Object {$null -ne $_.CPUCelsius} | Measure-Object CPUCelsius -Maximum).Maximum
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{
        Test=$(if($Kind -eq 'gpu'){'OpenGL-1280x720-256shader-b8-w5-30s-v2'}else{'RAM-copy-128MiB-20s-v1'})
        Timestamp=(Get-Date).ToString('o');Seconds=$worker.Seconds;Workers=1;Runtime=[Environment]::Version.ToString()
        Completed=($null -eq $reason);StopReason=$reason;MiBPerSecond=$rate;GpuFramesPerSecond=$gpuRate;GPUName=$gpuName
        Renderer=$(if($Kind -eq 'gpu'){$worker.Renderer}else{$null});BufferMiB=$(if($Kind -eq 'memory'){128}else{$null})
        RateSamples=@($rates.ToArray()); WarmupSeconds=$(if($Kind -eq 'gpu'){5}else{0})
        PeakCPU=$peak;Frames=@($frames.ToArray())
        Limitations=$(if($Kind -eq 'gpu'){'Five-second unscored warm-up, then 30-second fixed 1280x720 offscreen OpenGL workload with 256 shader iterations. Eight draws per glFinish; wall-clock draws/s includes driver overhead. Temperature peaks include warm-up. Scores are incompatible with GPU v1. Not game FPS or overall GPU performance. Driver and CPU overhead affect results. Default OpenGL GPU only; matching GPU temperature required.'}else{'128 MiB buffer copied repeatedly using Buffer.BlockCopy; 256 MiB allocation. CPU, caches and runtime affect throughput. Copy bytes counted once, not read-plus-write traffic. Sampled buffer check is not a full RAM integrity test.'})
    }}
}
