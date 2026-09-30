# PC Insight 0.1 - local-only, read-only collection and bounded CPU test.
function Get-PCSnapshot {
    $warnings = [System.Collections.Generic.List[string]]::new()
    function Query($name) {
        try { @(Get-CimInstance -ClassName $name -OperationTimeoutSec 8 -ErrorAction Stop) }
        catch { $warnings.Add("$name unavailable: $($_.Exception.Message)"); @() }
    }
    $cpu = @(Query 'Win32_Processor')
    $ram = @(Query 'Win32_PhysicalMemory')
    $os = @(Query 'Win32_OperatingSystem')
    $gpu = @(Query 'Win32_VideoController')
    $board = @(Query 'Win32_BaseBoard')
    $bios = @(Query 'Win32_BIOS')
    $disks = @(Query 'Win32_LogicalDisk' | Where-Object DriveType -eq 3)
    $total = $null; $free = $null; $used = $null
    if ($os.Count -gt 0 -and $os[0].TotalVisibleMemorySize -gt 0) {
        $total = [math]::Round($os[0].TotalVisibleMemorySize / 1MB, 1)
        $free = [math]::Round($os[0].FreePhysicalMemory / 1MB, 1)
        $used = [math]::Round(100 * (1 - $os[0].FreePhysicalMemory / $os[0].TotalVisibleMemorySize), 1)
    }
    $gpuTelemetry = @()
    # Use only known installed vendor locations, never a PATH-resolved executable.
    $smiPaths = @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")
    $smi = $smiPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($smi) {
        try {
            $lines = & $smi '--query-gpu=name,utilization.gpu,temperature.gpu,power.draw,memory.total' '--format=csv,noheader,nounits' 2>$null
            if ($LASTEXITCODE -eq 0) {
                $gpuTelemetry = @($lines | ConvertFrom-Csv -Header Name,Utilization,Temperature,Power,MemoryMiB)
            } else { $warnings.Add('NVIDIA live telemetry unavailable.') }
        } catch { $warnings.Add('NVIDIA live telemetry unavailable.') }
    }
    [pscustomobject]@{
        Schema = 1; Timestamp = (Get-Date).ToString('o')
        CPU = @($cpu | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,LoadPercentage,MaxClockSpeed)
        RAM = @($ram | Select-Object DeviceLocator,Capacity,ConfiguredClockSpeed,Speed)
        MemoryTotalGiB = $total; MemoryFreeGiB = $free; MemoryUsedPercent = $used
        GPU = @($gpu | Select-Object Name,DriverVersion,VideoProcessor)
        GPUTelemetry = $gpuTelemetry
        Board = @($board | Select-Object Manufacturer,Product)
        BIOS = @($bios | Select-Object SMBIOSBIOSVersion)
        OS = @($os | Select-Object Caption,Version)
        Disks = @($disks | Select-Object DeviceID,Size,FreeSpace)
        Warnings = @($warnings)
    }
}
function Get-PCInsights($s) {
    $items = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $s.MemoryUsedPercent -and $s.MemoryUsedPercent -ge 85) {
        $items.Add("[HIGH | measured] Memory use is $($s.MemoryUsedPercent)%. Close unused applications, then repeat your workload. Consider more RAM only if pressure persists during normal use.")
    } else { $items.Add('[INFO] A memory snapshot alone cannot establish whether you need a RAM upgrade. Scan while your usual game or application is running.') }
    foreach ($d in $s.Disks) {
        if ($d.Size -gt 0 -and ($d.FreeSpace / $d.Size) -lt 0.15) {
            $items.Add("[MEDIUM | measured] $($d.DeviceID) has less than 15% free space. Review storage usage and move unneeded files; nothing will be deleted automatically.")
        }
    }
    foreach ($c in $s.CPU) {
        if ($null -ne $c.LoadPercentage -and $c.LoadPercentage -ge 85) {
            $items.Add('[CHECK | measured] CPU load was at least 85% during this snapshot. Check background applications and repeat during the workload. This is not proof of a CPU bottleneck.')
        }
    }
    foreach ($g in $s.GPUTelemetry) {
        $temp = 0.0
        if ([double]::TryParse($g.Temperature.Trim(), [ref]$temp) -and $temp -ge 85) {
            $items.Add('[CHECK | measured] GPU temperature is at least 85 C. Check the exact model limits, airflow and fan operation before considering higher power. This threshold does not diagnose throttling.')
        }
    }
    $items.Add('[RAM] Configured memory speed is reported by firmware. This build cannot confirm XMP/EXPO support or whether a profile is enabled. Check motherboard documentation before making BIOS changes.')
    $items.Add('[TUNING] CPU tuning provides saved baseline/retest experiments for external changes. CPU clock/voltage and RAM writes are unavailable. Supported NVIDIA GPU controls are on Tuning; compatibility must be detected.')
    $items.Add('[NEXT STEP] Run three CPU baseline tests with the same background applications, power source and cooling conditions. Change one supported setting, then repeat and compare.')
    @($items)
}
function Invoke-PCBenchmark {
    # A repeatable single-worker SHA-256 workload, not a comprehensive CPU score.
    $data = New-Object byte[] 1048576
    $rng = [Random]::new(42); $rng.NextBytes($data)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        1..3 | ForEach-Object { $null = $hash.ComputeHash($data) }
        $watch = [Diagnostics.Stopwatch]::StartNew(); $count = 0
        while ($watch.Elapsed.TotalSeconds -lt 15) { $null = $hash.ComputeHash($data); $count++ }
        $watch.Stop()
        [pscustomobject]@{ Test = 'SHA256-1MiB-single-v1'; Timestamp = (Get-Date).ToString('o'); Seconds = $watch.Elapsed.TotalSeconds; MiBPerSecond = [math]::Round($count / $watch.Elapsed.TotalSeconds, 2); Runtime = [Environment]::Version.ToString() }
    } finally { $hash.Dispose() }
}
