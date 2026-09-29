# Direct read-only integration. No GUI, web server, CSV or WMI provider required.
function Initialize-PCNativeSensors {
    if ($script:NativeComputer) { return }
    $folder = Join-Path $PSScriptRoot 'vendor\LibreHardwareMonitor'
    $manifest = Get-Content (Join-Path $folder 'hashes.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest) {
        $path = Join-Path $folder $entry.Name
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Bundled sensor file is missing or changed: $($entry.Name). Extract the complete app ZIP again." }
    }
    try {
        $null = [Reflection.Assembly]::LoadFrom((Join-Path $folder 'LibreHardwareMonitorLib.dll'))
        $script:NativeComputer = New-Object LibreHardwareMonitor.Hardware.Computer
        $script:NativeComputer.IsCpuEnabled = $true
        $script:NativeComputer.IsGpuEnabled = $true
        # Keep unrelated motherboard, storage, fan and controller access disabled.
        $script:NativeComputer.Open()
    } catch {
        Close-PCNativeSensors
        throw "Built-in sensor initialization failed: $($_.Exception.Message)"
    }
}
function Close-PCNativeSensors {
    if ($script:NativeComputer) {
        try { $script:NativeComputer.Close() } catch { }
        $script:NativeComputer = $null
    }
}
function Read-PCNativeHardware($hardware) {
    $hardware.Update()
    foreach ($sensor in $hardware.Sensors) {
        $kind = [string]$sensor.SensorType
        if ($kind -notin @('Temperature','Clock','Load','Power')) { continue }
        if ($null -eq $sensor.Value) { continue }
        $number = [double]$sensor.Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { continue }
        [pscustomobject]@{
            Name=[string]$sensor.Name; Type=$kind; Value=$number
            Identifier=[string]$sensor.Identifier; Parent=[string]$hardware.Identifier; HardwareName=[string]$hardware.Name
        }
    }
    foreach ($child in $hardware.SubHardware) { Read-PCNativeHardware $child }
}
function Get-PCNativeFrame {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $rows = @(); $issue = $null
    try {
        if (-not $script:NativeComputer) { throw 'Built-in sensors are not initialized.' }
        $rows = @(foreach ($hardware in $script:NativeComputer.Hardware) { Read-PCNativeHardware $hardware })
    } catch { $issue = $_.Exception.Message }
    $temps = @($rows | Where-Object {
        $_.Parent -match '^/(intelcpu|amdcpu)/' -and $_.Type -eq 'Temperature' -and
        $_.Name -notmatch '(?i)distance|tjmax|headroom|critical|limit' -and $_.Value -gt 0 -and $_.Value -lt 125
    })
    $peak = $null
    if ($temps.Count -gt 0) { $peak = ($temps | Measure-Object Value -Maximum).Maximum }
    if ($null -eq $peak -and -not $issue) {
        $issue = 'No direct CPU temperature is available. Close PC Insight and use Start-PC-Insight-Admin.cmd. If already elevated, the PawnIO hardware-access driver may be missing or blocked; see README. Do not disable Windows security settings.'
    }
    $watch.Stop()
    [pscustomobject]@{
        Timestamp=(Get-Date).ToString('o'); QuerySeconds=$watch.Elapsed.TotalSeconds
        CPUCelsius=$peak; Sensors=$rows; Issue=$issue; Provider='Built-in LibreHardwareMonitorLib 0.9.6'
        SampleTimestamp=$null; SampleAgeSeconds=$null
        Freshness='Hardware.Update called for this query. Sensor-level timestamps are not supplied; hardware freshness is not guaranteed.'
    }
}
