function Convert-PCSensorRows($rows) {
    @($rows | Where-Object {
        $_.SensorType -in @('Temperature','Clock','Load','Power') -and
        $null -ne $_.Value -and -not [double]::IsNaN([double]$_.Value) -and -not [double]::IsInfinity([double]$_.Value)
    } | ForEach-Object {
        [pscustomobject]@{ Name=[string]$_.Name; Type=[string]$_.SensorType; Value=[double]$_.Value; Identifier=[string]$_.Identifier; Parent=[string]$_.Parent }
    })
}
function Get-PCSensorFrame {
    Get-PCNativeFrame
}
function Get-PCWMISensorFrame {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $rows = @(); $issue = $null
    try {
        if (-not (Get-Process -Name LibreHardwareMonitor -ErrorAction SilentlyContinue)) { throw 'Libre Hardware Monitor is not running.' }
        $raw = @(Get-CimInstance -Namespace 'root\LibreHardwareMonitor' -ClassName Sensor -OperationTimeoutSec 2 -ErrorAction Stop)
        $rows = @(Convert-PCSensorRows $raw)
        if ($rows.Count -eq 0) { throw 'The provider returned no sensor values. Check its WMI option and permissions.' }
    } catch { $issue = $_.Exception.Message }
    $watch.Stop()
    $temps = @($rows | Where-Object { $_.Parent -match '^/(intelcpu|amdcpu)/' -and $_.Type -eq 'Temperature' -and $_.Name -notmatch '(?i)distance|tjmax|headroom|critical|limit' -and $_.Value -gt 0 -and $_.Value -lt 125 })
    $peak = $null
    if ($temps.Count -gt 0) { $peak = ($temps | Measure-Object Value -Maximum).Maximum }
    [pscustomobject]@{ Timestamp=(Get-Date).ToString('o'); QuerySeconds=$watch.Elapsed.TotalSeconds; CPUCelsius=$peak; Sensors=$rows; Issue=$issue; Provider='LibreHardwareMonitor WMI'; Freshness='Query time only; provider does not expose a sample timestamp.' }
}
function Get-PCStopReason($frame) {
    $temperature=0.0;$querySeconds=0.0
    if ($frame.Issue) { return "Sensor unavailable: $($frame.Issue)" }
    if ($null -eq $frame.CPUCelsius -or $frame.CPUCelsius -is [bool] -or -not [double]::TryParse([string]$frame.CPUCelsius,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$temperature) -or [double]::IsNaN($temperature) -or [double]::IsInfinity($temperature) -or $temperature -le 0) { return 'No valid CPU temperature sensor is available.' }
    if ($null -eq $frame.QuerySeconds -or $frame.QuerySeconds -is [bool] -or -not [double]::TryParse([string]$frame.QuerySeconds,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$querySeconds) -or [double]::IsNaN($querySeconds) -or [double]::IsInfinity($querySeconds) -or $querySeconds -lt 0 -or $querySeconds -gt 3) { return 'Sensor query duration is invalid or exceeded the 3-second response limit.' }
    if ($temperature -ge 85) { return 'CPU temperature reached the 85 C preview cutoff.' }
    return $null
}
function Initialize-PCWorkers {
    if ('PCInsightWorkload' -as [type]) { return }
    Add-Type -Path "$PSScriptRoot\Workload.cs"
}
function Invoke-PCSensorSession([switch]$WithLoad, [ValidateSet(20,60)][int]$DurationSeconds = 20, [scriptblock]$Guard) {
    $frames = [System.Collections.Generic.List[object]]::new()
    $worker = $null; $reason = $null; $rate = $null; $workers = 0
    if($Guard){& $Guard}
    $first = Get-PCSensorFrame
    $frames.Add($first)
    [pscustomobject]@{ Kind='Frame'; Value=$first }
    if ($WithLoad) {
        $reason = Get-PCStopReason $first
        if ($reason) { throw "CPU test was not started. $reason" }
        if($Guard){& $Guard}
        Initialize-PCWorkers
        # Reserve one logical processor where possible; cap load and memory footprint.
        $workers = [math]::Max(1, [math]::Min(16, [Environment]::ProcessorCount - 1))
        $worker = [PCInsightWorkload]::new()
        $worker.Start($workers, $DurationSeconds)
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
            if($Guard){& $Guard}
            Start-Sleep -Milliseconds 1000
            if($Guard){& $Guard}
            $frame = Get-PCSensorFrame
            $frames.Add($frame)
            [pscustomobject]@{ Kind='Frame'; Value=$frame }
            [pscustomobject]@{ Kind='Progress'; Value=[math]::Min(100,100*$watch.Elapsed.TotalSeconds/$DurationSeconds) }
            if ($WithLoad) {
                $reason = Get-PCStopReason $frame
                if ($reason) { break }
                if ($worker.Error) { $reason = 'CPU workload failed: ' + $worker.Error; break }
                if ($worker.Done) { break }
            }
        }
    } finally { if ($worker) { $worker.Stop() }; $watch.Stop() }
    if ($worker -and -not $reason -and $worker.Error) { $reason = 'CPU workload failed: ' + $worker.Error }
    if ($worker -and -not $reason -and $worker.Seconds -gt 0) { $rate = [math]::Round($worker.CompletedMiB / $worker.Seconds, 2) }
    $valid = @($frames | Where-Object { $null -ne $_.CPUCelsius })
    $peak = $null
    if ($valid.Count -gt 0) { $peak = ($valid | Measure-Object CPUCelsius -Maximum).Maximum }
    $result = [pscustomobject]@{
        Test=$(if ($WithLoad -and $DurationSeconds -eq 60) { 'SHA256-1MiB-parallel-60s-v1' } elseif ($WithLoad) { 'SHA256-1MiB-parallel-v2' } else { 'Sensors-only-v1' })
        Timestamp=(Get-Date).ToString('o'); Seconds=$(if ($worker) { $worker.Seconds } else { $watch.Elapsed.TotalSeconds }); MiBPerSecond=$rate
        Workers=$workers; Runtime=[Environment]::Version.ToString(); Completed=($null -eq $reason)
        StopReason=$reason; PeakCPU=$peak; Frames=@($frames.ToArray())
        Limitations='Short workload or recording, not a stability test. Clocks are provider-reported, not necessarily effective clocks. Direct sensor updates are requested; hardware sample timestamps are unavailable, so freshness cannot be guaranteed. No FPS measurement.'
    }
    [pscustomobject]@{ Kind='Result'; Value=$result }
}
