function Initialize-PCMemoryReader {
    if ('PCInsightMemory' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PCInsightMemory {
 [StructLayout(LayoutKind.Sequential)] public struct Status {
  public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPage, AvailablePage, TotalVirtual, AvailableVirtual, AvailableExtended;
 }
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx(ref Status value);
 public static double Read() { var s=new Status(); s.Length=(uint)Marshal.SizeOf(typeof(Status)); if(!GlobalMemoryStatusEx(ref s)) return double.NaN; return s.Load; }
}
'@
}
function Add-PCMemorySample($frame) {
    $used = $null
    try { Initialize-PCMemoryReader; $v = [PCInsightMemory]::Read(); if (-not [double]::IsNaN($v)) { $used = $v } } catch { }
    $frame | Add-Member -NotePropertyName MemoryUsedPercent -NotePropertyValue $used -Force
    $frame
}
function Invoke-PCContinuousSession([string]$StopPath) {
    $frames = [Collections.Generic.Queue[object]]::new()
    $watch = [Diagnostics.Stopwatch]::StartNew(); $count = 0
    while (-not (Test-Path -LiteralPath $StopPath)) {
        $frame = Add-PCMemorySample (Get-PCSensorFrame)
        $frames.Enqueue($frame); $count++
        while ($frames.Count -gt 300) { $null = $frames.Dequeue() }
        [pscustomobject]@{Kind='Frame';Value=$frame}
        for ($i=0; $i -lt 10 -and -not (Test-Path -LiteralPath $StopPath); $i++) { Start-Sleep -Milliseconds 100 }
    }
    $watch.Stop()
    $rows = @($frames.ToArray())
    $peak = ($rows | Where-Object { $null -ne $_.CPUCelsius } | Measure-Object CPUCelsius -Maximum).Maximum
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{
        Test='Continuous-monitor-v1'; Timestamp=(Get-Date).ToString('o'); Seconds=$watch.Elapsed.TotalSeconds
        Workers=0; Runtime=[Environment]::Version.ToString(); Completed=$true; StopReason=$null; MiBPerSecond=$null
        PeakCPU=$peak; Frames=$rows; TotalQueries=$count; RetainedQueries=$rows.Count
        Limitations='Read-only monitoring. Only the latest 300 samples are retained; peaks and diagnostics refer to that window. No workload is added. Sensor timestamps are unavailable. Not a stability test.'
    }}
}
function Get-PCMeasuredInsights($frames) {
    $rows = @($frames); $messages = [Collections.Generic.List[string]]::new()
    if ($rows.Count -eq 0) { return 'Start live monitoring during your usual workload to collect diagnostic evidence.' }
    $seconds = 0
    if ($rows.Count -gt 1) { $seconds = ([datetimeoffset]::Parse([string]$rows[-1].Timestamp) - [datetimeoffset]::Parse([string]$rows[0].Timestamp)).TotalSeconds }
    $messages.Add(('OBSERVATION WINDOW: {0} samples across {1:N0} seconds. Thresholds below are diagnostic heuristics, not hardware limits.' -f $rows.Count,$seconds))
    $issues = @($rows | Where-Object { $_.Issue })
    if ($issues.Count) { $messages.Add("DATA QUALITY: $($issues.Count) of $($rows.Count) queries reported sensor issues. Missing readings are not treated as zero. Latest issue: $($issues[-1].Issue)") }
    if ($rows.Count -lt 10 -or $seconds -lt 10) { $messages.Add('Collect at least 10 samples spanning 10 seconds before interpreting load patterns.'); return $messages.ToArray() }
    $series = @{}
    foreach ($f in $rows) {
        if ($null -ne $f.MemoryUsedPercent) {
            if (-not $series.ContainsKey('RAM usage')) { $series['RAM usage'] = @() }
            $series['RAM usage'] += [double]$f.MemoryUsedPercent
        }
        foreach ($sensor in $f.Sensors) {
            $key = $null
            if ($sensor.Type -eq 'Load' -and $sensor.Parent -match '^/(intelcpu|amdcpu)/' -and $sensor.Name -eq 'CPU Total') { $key = "CPU load ($($sensor.Parent))" }
            if ($sensor.Type -eq 'Load' -and $sensor.Parent -match '^/gpu' -and $sensor.Name -eq 'GPU Core') { $key = "GPU load ($($sensor.Parent))" }
            if ($key -and $null -ne $sensor.Value -and $sensor.Value -ge 0 -and $sensor.Value -le 100) {
                if (-not $series.ContainsKey($key)) { $series[$key] = @() }
                $series[$key] += [double]$sensor.Value
            }
        }
    }
    foreach ($key in @($series.Keys | Sort-Object)) {
        $values = @($series[$key]); $stats = $values | Measure-Object -Average -Maximum
        $messages.Add(('{0}: average {1:N1}%, peak {2:N1}%; {3}/{4} samples available.' -f $key,$stats.Average,$stats.Maximum,$values.Count,$rows.Count))
        if ($values.Count -lt 10 -or $values.Count -lt 0.8 * $rows.Count) { $messages.Add('Coverage is too low for a sustained-load interpretation.'); continue }
        $high = @($values | Where-Object { $_ -ge 90 }).Count / $values.Count
        if ($high -ge 0.8) {
            if ($key -like 'RAM*') { $messages.Add('MEMORY PRESSURE CANDIDATE: usage reached 90% in at least 80% of available samples. Close unused applications and repeat the same workload. Paging and application demand must be checked before recommending more RAM.') }
            elseif ($key -like 'GPU*') { $messages.Add('GPU LOAD CANDIDATE: load reached 90% in at least 80% of available samples. If game performance is poor, compare the same scene with lower rendering resolution. This alone does not establish a GPU bottleneck.') }
            else { $messages.Add('CPU LOAD CANDIDATE: total load reached 90% in at least 80% of available samples. Check which applications are active and repeat the same workload with unnecessary background work closed. High load during a CPU benchmark is expected.') }
        }
    }
    foreach ($label in 'RAM usage','CPU load','GPU load') {
        if (-not @($series.Keys | Where-Object { $_ -like "$label*" }).Count) { $messages.Add("$label unavailable in this window; no conclusion can be drawn.") }
    }
    $temps = @($rows | Where-Object { $null -ne $_.CPUCelsius } | ForEach-Object { $_.CPUCelsius })
    if ($temps.Count) {
        $max = ($temps | Measure-Object -Maximum).Maximum
        $messages.Add("CPU TEMPERATURE: sampled peak $max C. This is not a thermal-throttling measurement.")
        if ($max -ge 85) { $messages.Add('TEMPERATURE REVIEW: a reading met the app''s 85 C review threshold. Check cooling and repeat under equivalent conditions before considering tuning. Continuous monitoring does not stop other applications or change hardware settings.') }
    }
    $messages.Add('No FPS, frame-time, paging or throttle-flag data is collected here. Low overall CPU load can hide a busy individual thread. These observations cannot prove a bottleneck or overclocking headroom.')
    $messages.ToArray()
}
