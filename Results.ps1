function Get-PCResultRate($result) {
    if ($null -ne $result.GpuFramesPerSecond) { return $result.GpuFramesPerSecond }
    return $result.MiBPerSecond
}
function Get-PCResultUnit($result) {
    if ($result.Test -like 'OpenGL-*') { return 'draws/s' }
    return 'MiB/s'
}
function Format-PCValue($value, $unit) {
    if ($null -eq $value) { return 'Unavailable' }
    return ('{0:N1} {1}' -f $value,$unit)
}
function Get-PCPreviousMatch($latest, $history) {
    @($history | Where-Object {
        $_.Timestamp -lt $latest.Timestamp -and $_.Test -eq $latest.Test -and
        $_.CPUName -eq $latest.CPUName -and $_.Runtime -eq $latest.Runtime -and
        $_.Workers -eq $latest.Workers -and (Get-PCResultRate $_) -gt 0 -and
        ($latest.Test -notlike 'OpenGL-*' -or ($_.Renderer -eq $latest.Renderer -and $_.DriverVersion -eq $latest.DriverVersion)) -and
        ($latest.Test -notlike 'RAM-*' -or $_.MemoryConfig -eq $latest.MemoryConfig) -and
        $_.Completed -ne $false -and -not $_.StopReason
    } | Sort-Object Timestamp | Select-Object -Last 1) | Select-Object -First 1
}
function Get-PCComparison($latest, $history) {
    if ($latest.StopReason -or $latest.Completed -eq $false -or $null -eq (Get-PCResultRate $latest)) {
        return 'No comparable score for this session.'
    }
    $previous = Get-PCPreviousMatch $latest $history
    if (-not $previous) { return 'No earlier matching completed test. Repeat this test to establish a baseline.' }
    $delta = 100 * ((Get-PCResultRate $latest) / (Get-PCResultRate $previous) - 1)
    $plan = 'Power plan unchanged.'
    if (-not $previous.Plan -or -not $latest.Plan) { $plan = 'Power-plan information incomplete.' }
    elseif ($previous.Plan -ne $latest.Plan) { $plan = 'Power plan changed between these runs.' }
    return ("Previous matching run: {0}`nThroughput: {1:N1} -> {2:N1} {5} ({3:+0.0;-0.0;0.0}%). {4}`nA single comparison cannot establish improvement. Repeat at least three times under equivalent conditions; this is not an FPS estimate." -f $previous.Timestamp,(Get-PCResultRate $previous),(Get-PCResultRate $latest),$delta,$plan,(Get-PCResultUnit $latest))
}
function Get-PCSessionSummary($session, $history) {
    if (-not $session) { return 'Run a monitored CPU test or record sensors to see a summary here.' }
    $frames = @($session.Frames)
    $temps = @(); $powers = @(); $gpu = @()
    foreach ($frame in $frames) {
        foreach ($sensor in $frame.Sensors) {
            if ($null -eq $sensor.Value) { continue }
            if ($sensor.Parent -match '^/(intelcpu|amdcpu)/') {
                if ($sensor.Type -eq 'Temperature' -and $sensor.Name -notmatch '(?i)distance|tjmax|headroom|critical|limit' -and $sensor.Value -gt 0 -and $sensor.Value -lt 125) { $temps += $sensor.Value }
                if ($sensor.Type -eq 'Power' -and $sensor.Name -eq 'CPU Package') { $powers += $sensor.Value }
            }
            if ($sensor.Parent -match '^/gpu' -and $sensor.Type -eq 'Temperature' -and $sensor.Name -eq 'GPU Core') { $gpu += $sensor.Value }
        }
    }
    $issues = @($frames | Where-Object { $_.Issue } | ForEach-Object { $_.Issue } | Select-Object -Unique)
    $state = 'Completed'
    if ($session.StopReason) { $state = 'Stopped: ' + $session.StopReason }
    elseif ($session.Completed -eq $false) { $state = 'Incomplete' }
    elseif ($issues.Count -gt 0 -or $temps.Count -eq 0) { $state = 'Completed with missing readings or sensor issues' }
    $lines = @(
        "LATEST SESSION | $state", "$($session.Timestamp) | $($session.Test)",
        ('Duration: {0:N1} seconds | Workers: {1} | Sensor queries: {2}' -f $session.Seconds,$session.Workers,$frames.Count),
        ('Peak CPU temperature: ' + (Format-PCValue (($temps | Measure-Object -Maximum).Maximum) 'C')),
        ('Peak CPU package power: ' + (Format-PCValue (($powers | Measure-Object -Maximum).Maximum) 'W')),
        ('Peak GPU core temperature: ' + (Format-PCValue (($gpu | Measure-Object -Maximum).Maximum) 'C')),
        ('Throughput: ' + (Format-PCValue (Get-PCResultRate $session) (Get-PCResultUnit $session))),
        ('Sensor source: ' + ((@($frames | ForEach-Object { $_.Provider } | Select-Object -Unique)) -join ', '))
    )
    if ($session.Test -eq 'Continuous-monitor-v1') { $lines += "Retained window: $($session.RetainedQueries) of $($session.TotalQueries) queries. Peaks and diagnostics cover only these retained samples." }
    if ($issues.Count) { $lines += 'Sensor issues: ' + ($issues -join '; ') }
    if ($session.Renderer) { $lines += 'OpenGL renderer: ' + $session.Renderer }
    if ($session.Limitations) { $lines += $session.Limitations }
    $lines += ''; $lines += Get-PCComparison $session $history
    $lines += ''; $lines += 'Peaks are sampled readings. This short test does not establish long-term stability, thermal throttling, or overclocking headroom.'
    $lines -join "`n"
}
