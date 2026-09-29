function Convert-PCLogLines([string[]]$lines, [datetime]$now = (Get-Date)) {
    if ($lines.Count -ne 3 -or -not $lines[0].StartsWith(',') -or -not $lines[1].StartsWith('Time,')) {
        throw 'This is not a supported Libre Hardware Monitor sensor log. Choose LibreHardwareMonitorLog-*.csv.'
    }
    $ids = $lines[0].Split(',')
    $values = $lines[2].Split(',')
    if ($ids.Count -ne $values.Count) { throw 'Log columns do not match the header. Wait for a complete sample or choose the current log.' }
    $stamp = [datetime]::MinValue
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (-not [datetime]::TryParseExact($values[0], 'MM/dd/yyyy HH:mm:ss', $culture, [Globalization.DateTimeStyles]::None, [ref]$stamp)) {
        throw 'No supported timestamp found. Enable Log Sensors and wait for new readings.'
    }
    $age = ($now - $stamp).TotalSeconds
    if ($age -gt 5 -or $age -lt -2) { throw 'Sensor log is stale or its timestamp is in the future. Set Logging Interval to 1 second and choose the active log.' }
    $headers = @(0..($ids.Count - 1) | ForEach-Object { "col$_" })
    $names = $lines[1] | ConvertFrom-Csv -Header $headers
    $sensors = [System.Collections.Generic.List[object]]::new()
    for ($i = 1; $i -lt $ids.Count; $i++) {
        $match = [regex]::Match($ids[$i], '^(?<parent>/.+)/(?<type>temperature|clock|load|power)/\d+$')
        if (-not $match.Success) { continue }
        $value = 0.0
        if (-not [double]::TryParse($values[$i], [Globalization.NumberStyles]::Float, $culture, [ref]$value)) { continue }
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { continue }
        $kind = $culture.TextInfo.ToTitleCase($match.Groups['type'].Value)
        $sensors.Add([pscustomobject]@{ Name=[string]$names.($headers[$i]); Type=$kind; Value=$value; Identifier=$ids[$i]; Parent=$match.Groups['parent'].Value })
    }
    [pscustomobject]@{ SampleTimestamp=$stamp.ToString('o'); SampleAgeSeconds=[math]::Round($age,2); Sensors=@($sensors.ToArray()) }
}
function Get-PCLogFrame([string]$path) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $rows = @(); $issue = $null; $age = $null; $stamp = $null
    try {
        if (-not ('PCInsightLogReader' -as [type])) { Add-Type -Path "$PSScriptRoot\LogReader.cs" }
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Choose an active LibreHardwareMonitorLog-*.csv file first.' }
        $sample = Convert-PCLogLines ([PCInsightLogReader]::Read($path))
        $rows = @($sample.Sensors); $stamp=$sample.SampleTimestamp; $age=$sample.SampleAgeSeconds
    } catch { $issue = $_.Exception.Message }
    $temps = @($rows | Where-Object { $_.Parent -match '^/(intelcpu|amdcpu)/' -and $_.Type -eq 'Temperature' -and $_.Name -notmatch '(?i)distance|tjmax|headroom|critical|limit' -and $_.Value -gt 0 -and $_.Value -lt 125 })
    $peak = $null
    if ($temps.Count -gt 0) { $peak = ($temps | Measure-Object Value -Maximum).Maximum }
    $watch.Stop()
    [pscustomobject]@{ Timestamp=(Get-Date).ToString('o'); QuerySeconds=$watch.Elapsed.TotalSeconds; CPUCelsius=$peak; Sensors=$rows; Issue=$issue; Provider='LibreHardwareMonitor local CSV'; SampleTimestamp=$stamp; SampleAgeSeconds=$age; Freshness='Log timestamp checked; must be within 5 seconds. Sensor hardware freshness is provider-dependent.' }
}
