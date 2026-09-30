#requires -Version 5.1
param([switch]$WaitForPreviousInstance)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
. "$PSScriptRoot\Engine.ps1"
. "$PSScriptRoot\Power.ps1"
. "$PSScriptRoot\Tuning.ps1"
. "$PSScriptRoot\GpuOverclock.ps1"
. "$PSScriptRoot\Profiles.ps1"
. "$PSScriptRoot\Updates.ps1"
. "$PSScriptRoot\Branding.ps1"
$script:appVersion=Get-PCAppVersion
. "$PSScriptRoot\Results.ps1"
. "$PSScriptRoot\SessionExport.ps1"
. "$PSScriptRoot\SessionDetails.ps1"
. "$PSScriptRoot\SessionComparison.ps1"
. "$PSScriptRoot\ComparisonReport.ps1"
. "$PSScriptRoot\SessionChart.ps1"
. "$PSScriptRoot\GuidedOptimize.ps1"
. "$PSScriptRoot\GuidedClocks.ps1"
. "$PSScriptRoot\GuidePresentation.ps1"
. "$PSScriptRoot\GameOverlay.ps1"
. "$PSScriptRoot\RepeatedTests.ps1"
. "$PSScriptRoot\LiveMonitor.ps1"
. "$PSScriptRoot\Monitor.ps1"
. "$PSScriptRoot\LogSensors.ps1"
. "$PSScriptRoot\NativeSensors.ps1"
$script:SensorLogPath = $null
$script:dataDir = Join-Path $env:LOCALAPPDATA 'PCInsight'
$null = New-Item -ItemType Directory -Path $dataDir -Force
$script:restorePath = Join-Path $dataDir 'restore.json'
$script:historyPath = Join-Path $dataDir 'history.json'
# One instance protects the recovery journal against concurrent changes.
$script:mutex = [Threading.Mutex]::new($false, 'Local\PCInsightPreview01')
if (-not $mutex.WaitOne($(if ($WaitForPreviousInstance) { 15000 } else { 0 }))) { [System.Windows.MessageBox]::Show('PC Insight is already open.') | Out-Null; exit }
$script:job = $null; $script:snapshot = $null; $script:history = @(); $script:jobKind = ''; $script:sessions = @(); $script:pendingResult = $null
try {
    [xml]$xaml = Get-Content -LiteralPath "$PSScriptRoot\MainWindow.xaml" -Raw -Encoding UTF8
    $reader = [Xml.XmlNodeReader]::new($xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Title='PC Insight | Preview '+$script:appVersion
    Set-PCWindowBranding -Window $window -Root $PSScriptRoot -Version $script:appVersion
    $script:ui = @{}
    'EnableOverlayHotkey','ToggleOverlay','OverlayStatus','LastFpsCapture','ExportFpsDetails','GuideDetect','GuideBaseline','GuideApply','GuideRestore','GuideKeep','GuideStop','GuideExport','GuideStage','GuideStatusCard','GuideNextAction','GuideResultTitle','GuideRecommendationLabel','GuideRecommendation','GuideBeforeScore','GuideAfterScore','GuideChange','GuideMessage','GuideDevice','GuideVerdict','GuideRecovery','SensorHistoryChart','SensorHistoryTitle','SensorHistoryScale','SensorHistoryTime','SessionSensorDetails','SessionCoverage','ExportSessionCsv','ExportSessionJson','SessionExportStatus','InstalledVersion','ReleaseNotes','LastUpdateCheck','UpdateFeed','CheckUpdate','DownloadUpdate','InstallUpdate','CancelUpdate','UpdateStatus','AccessStatus','ReopenAdmin','OpenAppFolder','OpenDataFolder','Scan','Export','ScanTime','Overview','Insights','Benchmark','Cancel','Results','PlansRefresh','Plans','Apply','Restore','PowerStatus','Status','SensorStart','MultiBenchmark','SensorReadings','SensorSummary','SensorCancel','SessionResults','CPUModel','GPUModel','RAMModel','CPUTemp','GPUTemp','RAMUsed','DashboardTest','ChartCaption','TemperatureChart','DashboardResult','CPUDetails','CPUReadingTime','GPUReadingTime','CPUPower','DashboardRecord','OpenResults','ResultPeak','ResultRate','ResultDelta','Navigation','MonitorStart','MonitorStop','RAMSampleLabel','UsageChart','LongCPU','MemoryTest','GPUTest','TestProgress','ProgressLabel','ResultRateLabel','DetectTuning','GPUDevice','PowerPreset','ApplyGPU','RestoreGPU','TuningStatus','CapabilityText','SaveBaseline','CompareBaseline','BaselineResult','RepeatCPU','RepeatRAM','RepeatGPU','BatchReport','SessionPicker','ProfileName','SaveProfile','ProfilePicker','LoadProfile','ProfileStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    'DetectClocks','ClockGPU','ClockInfo','CoreOffset','MemoryOffset','ApplyClocks','RestoreClocks','ClockStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    'CoreTrialStart','CoreTrialApply','CoreTrialKeep','CoreTrialRestore','CoreTrialCancel','CoreTrialStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    'CompareSessionPicker','ComparisonRows','ComparisonStatus','ComparisonNotes','ExportComparison','ExportComparisonReport','ComparisonExportStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    'Endurance5','Endurance10','EnduranceStop','EnduranceStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }
    . "$PSScriptRoot\SessionComparisonUI.ps1"
    $ui.InstalledVersion.Text='Installed version: '+$script:appVersion
    $script:isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $ui.AccessStatus.Text = if ($script:isAdministrator) { 'Administrator access - sensor availability depends on hardware and drivers' } else { 'Standard access - some hardware sensors may be unavailable' }
    $ui.ReopenAdmin.Visibility = if ($script:isAdministrator) { 'Collapsed' } else { 'Visible' }
    $ui.ReopenAdmin.Add_Click({
        if ($script:job) { return }
        try {
            $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $main = Join-Path $PSScriptRoot 'Start-App.ps1'
            $null = Start-Process -FilePath $exe -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -WaitForPreviousInstance' -f $main) -ErrorAction Stop
            $window.Close()
        } catch {
            $ui.Status.Text = 'Administrator restart was cancelled or failed. This window remains open.'
        }
    })
    $ui.OpenAppFolder.Add_Click({ try { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $PSScriptRoot) } catch { Show-Error $_.Exception.Message } })
    $ui.OpenDataFolder.Add_Click({ try { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:dataDir) } catch { Show-Error $_.Exception.Message } })
    $script:profilesPath = Join-Path $dataDir 'profiles'
    $script:gpuJournalPath = Join-Path $dataDir 'gpu-power-restore.json'
    $script:baselinePath = Join-Path $dataDir 'tuning-baseline.json'
    $script:capabilities = $null; $script:baseline = $null
    if (Test-Path $script:baselinePath) {
        try { $script:baseline = Get-Content $script:baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $ui.BaselineResult.Text = 'Saved baseline could not be read.' }
    }
    if (Test-Path $script:gpuJournalPath) { $ui.TuningStatus.Text = 'A GPU recovery record exists. Refresh compatibility to inspect current settings, or restore the saved limit.' }
    $script:stopPath = Join-Path $dataDir ('monitor-stop-' + [guid]::NewGuid().ToString() + '.signal')
    $script:lastFrameTime = Get-Date
    $script:chartFrames = @()
    function Show-Chart($frames) {
        $ui.TemperatureChart.Children.Clear()
        $ui.UsageChart.Children.Clear()
        $rows = @($frames)
        if ($rows.Count -eq 0) { return }
        $start = [datetimeoffset]::Parse([string]$rows[0].Timestamp)
        $end = [datetimeoffset]::Parse([string]$rows[-1].Timestamp)
        $span = [math]::Max(1, ($end - $start).TotalSeconds)
        $line = $null
        foreach ($f in $rows) {
            if ($null -eq $f.CPUCelsius -or $f.Issue) { $line = $null; continue }
            if (-not $line) {
                $line = [Windows.Shapes.Polyline]::new()
                $line.Stroke = [Windows.Media.Brushes]::MediumPurple; $line.StrokeThickness = 2
                $null = $ui.TemperatureChart.Children.Add($line)
            }
            $x = 800 * (([datetimeoffset]::Parse([string]$f.Timestamp) - $start).TotalSeconds / $span)
            $y = 150 * (1 - [math]::Min(125,[math]::Max(0,[double]$f.CPUCelsius)) / 125)
            $line.Points.Add([Windows.Point]::new($x,$y))
        }
        foreach ($metric in 'CPU','GPU','RAM') {
            $line = $null
            foreach ($f in $rows) {
                $number = $null
                if ($metric -eq 'RAM') { $number = $f.MemoryUsedPercent }
                else {
                    $parent = '^/(intelcpu|amdcpu)/'; $name = 'CPU Total'
                    if ($metric -eq 'GPU') { $parent = '^/gpu'; $name = 'GPU Core' }
                    $sensor = $f.Sensors | Where-Object { $_.Parent -match $parent -and $_.Type -eq 'Load' -and $_.Name -eq $name } | Select-Object -First 1
                    if ($sensor) { $number = $sensor.Value }
                }
                if ($null -eq $number) { $line = $null; continue }
                if (-not $line) {
                    $line = [Windows.Shapes.Polyline]::new(); $line.StrokeThickness = 2
                    $line.Stroke = switch ($metric) { 'CPU' { [Windows.Media.Brushes]::MediumPurple } 'GPU' { [Windows.Media.Brushes]::Turquoise } 'RAM' { [Windows.Media.Brushes]::Goldenrod } }
                    $null = $ui.UsageChart.Children.Add($line)
                }
                $x = 800 * (([datetimeoffset]::Parse([string]$f.Timestamp) - $start).TotalSeconds / $span)
                $line.Points.Add([Windows.Point]::new($x,100 * (1 - [math]::Min(100,[math]::Max(0,[double]$number)) / 100)))
            }
        }
        $ui.ChartCaption.Text = "Recorded $(([datetimeoffset]::Parse([string]$rows[-1].Timestamp)).ToLocalTime().ToString('MMM d, HH:mm:ss')) | $($rows.Count) samples over $([math]::Round($span,1)) seconds"
    }
    function Show-SensorHistory {
        $ui.SensorHistoryChart.Children.Clear()
        $detail=$ui.SessionSensorDetails.SelectedItem
        $selected=$ui.SessionPicker.SelectedItem
        $ui.SensorHistoryTitle.Text='Select a sensor row to inspect its history.'
        $ui.SensorHistoryScale.Text='';$ui.SensorHistoryTime.Text=''
        if(-not $detail -or -not $selected){return}
        $ui.SensorHistoryTitle.Text="$($detail.Device) / $($detail.Sensor) / $($detail.Type)"
        $series=@(Get-PCSessionSensorSeries $selected.Session $detail)
        $plot=Get-PCSessionPlot $series
        if(-not $plot){$ui.SensorHistoryTime.Text='No valid timestamped readings are available.';return}
        $ui.SensorHistoryScale.Text=('{0:N1} to {1:N1} {2} (automatic scale)' -f $plot.Minimum,$plot.Maximum,$detail.Unit)
        $ui.SensorHistoryTime.Text=('{0:N1} seconds from first retained timestamp; {1}/{2} samples plotted. Hover over a point for its reading. Gaps are not filled.' -f $plot.Seconds,$plot.Samples,$plot.RetainedFrames)
        $line=$null
        foreach($point in $plot.Points){
            if($point.BreakBefore -or -not $line){
                $line=[Windows.Shapes.Polyline]::new()
                $line.Stroke=[Windows.Media.Brushes]::MediumPurple;$line.StrokeThickness=2
                $null=$ui.SensorHistoryChart.Children.Add($line)
            }
            $line.Points.Add([Windows.Point]::new($point.X,$point.Y))
            $dot=[Windows.Shapes.Ellipse]::new();$dot.Width=5;$dot.Height=5
            $dot.Fill=[Windows.Media.Brushes]::Turquoise
            $dot.ToolTip=('{0} | {1:N2} {2}' -f $point.Timestamp,$point.Value,$detail.Unit)
            [Windows.Controls.Canvas]::SetLeft($dot,$point.X-2.5)
            [Windows.Controls.Canvas]::SetTop($dot,$point.Y-2.5)
            $null=$ui.SensorHistoryChart.Children.Add($dot)
        }
    }
    $ui.SessionSensorDetails.Add_SelectionChanged({Show-SensorHistory})
    function Refresh-SessionPicker {
        $items=@($script:sessions | Sort-Object Timestamp -Descending | ForEach-Object {
            $state='Completed';if($_.StopReason -or $_.Completed -eq $false){$state='Stopped'}
            [pscustomobject]@{Label="$($_.Timestamp) · $($_.Test) · $state";Session=$_}
        })
        $ui.SessionPicker.ItemsSource=$items
        if($items.Count){$ui.SessionPicker.SelectedIndex=0}
        Refresh-PCComparisonReferences
    }
    $ui.SessionPicker.Add_SelectionChanged({
        if($ui.SessionPicker.SelectedItem){$ui.SessionResults.Text=Get-PCSessionSummary $ui.SessionPicker.SelectedItem.Session $script:history}
        $selected=$ui.SessionPicker.SelectedItem
        $ui.SessionSensorDetails.ItemsSource=@(Get-PCSessionSensorDetails $selected.Session)
        Show-SensorHistory
        $frames=@($selected.Session.Frames|Where-Object{$null -ne $_})
        $issues=@($frames|Where-Object{$_.Issue}).Count
        $ui.SessionCoverage.Text="$($frames.Count) retained samples; $issues samples with sensor issues excluded. Averages are sample means, not time-weighted. Raw sensor headroom is labeled separately."
        $available=$null -ne $ui.SessionPicker.SelectedItem
        $ui.ExportSessionCsv.IsEnabled=$available -and -not $script:job -and -not $script:updateJob
        $ui.ExportSessionJson.IsEnabled=$available -and -not $script:job -and -not $script:updateJob
        $ui.SessionExportStatus.Text='CSV includes retained raw sensor readings, identifiers and issues. Missing readings stay blank.'
        Refresh-PCComparisonReferences
    })
    function Export-SelectedSession([string]$format) {
        if($script:job -or $script:updateJob -or -not $ui.SessionPicker.SelectedItem){return}
        try {
            $session=$ui.SessionPicker.SelectedItem.Session
            $dialog=[Microsoft.Win32.SaveFileDialog]::new()
            $dialog.Filter=if($format -eq 'csv'){'CSV sensor readings (*.csv)|*.csv'}else{'JSON session (*.json)|*.json'}
            $dialog.FileName='PC-Insight-session-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.'+$format
            if($dialog.ShowDialog() -ne $true){return}
            if($format -eq 'csv'){
                $count=Export-PCSessionCsv $session $dialog.FileName
                $ui.SessionExportStatus.Text="Exported $count sensor rows from the selected session. Only retained samples are included."
            }else{
                Save-JsonAtomic ([pscustomobject]@{Schema=1;AppVersion=$script:appVersion;SensorSession=$session}) $dialog.FileName
                $ui.SessionExportStatus.Text='Exported the selected session and its recorded benchmark fields.'
            }
        }catch{Show-Error $_.Exception.Message}
    }
    $ui.ExportSessionCsv.Add_Click({Export-SelectedSession 'csv'})
    $ui.ExportSessionJson.Add_Click({Export-SelectedSession 'json'})
    function Show-DashboardResult {
        Refresh-SessionPicker
        $last = $script:sessions | Select-Object -Last 1
        if (-not $last) { return }
        $state = 'Completed'
        if ($last.StopReason) { $state = 'Stopped: ' + $last.StopReason }
        elseif ($last.Completed -eq $false) { $state = 'Incomplete' }
        elseif (@($last.Frames | Where-Object { $_.Issue }).Count) { $state = 'Completed with sensor issues' }
        $ui.DashboardResult.Text = "$state | $($last.Timestamp) | $([math]::Round($last.Seconds,1)) seconds"
        $peak = @($last.Frames | ForEach-Object { $_.Sensors } | Where-Object { $_.Parent -match '^/(intelcpu|amdcpu)/' -and $_.Type -eq 'Temperature' -and $_.Name -notmatch '(?i)distance|tjmax|headroom|critical|limit' -and $_.Value -gt 0 -and $_.Value -lt 125 } | Measure-Object Value -Maximum)
        if ($last.Test -eq 'Continuous-monitor-v1') { $ui.DashboardResult.Text += " | Peaks: latest $($last.RetainedQueries) samples only" }
        $ui.ResultPeak.Text = Format-PCValue $peak[0].Maximum '°C'
        $ui.ResultRateLabel.Text = if ($last.GpuFramesPerSecond -ne $null) { 'SHADER DRAWS / SECOND' } elseif ($last.Test -like 'RAM-*') { 'BUFFER COPY / SECOND' } else { 'SHA-256 THROUGHPUT' }
        $ui.ResultRate.Text = Format-PCValue (Get-PCResultRate $last) (Get-PCResultUnit $last)
        $ui.ResultDelta.Text = 'No match'
        if ($last.Completed -ne $false -and -not $last.StopReason -and (Get-PCResultRate $last) -gt 0) {
            $previous = Get-PCPreviousMatch $last $script:history
            if ($previous) { $ui.ResultDelta.Text = '{0:+0.0;-0.0;0.0}%' -f (100 * ((Get-PCResultRate $last) / (Get-PCResultRate $previous) - 1)) }
        }
        Show-Chart $last.Frames
    }

    function Show-MeasuredInsights {
        $base = @(); if ($script:snapshot) { $base = @(Get-PCInsights $script:snapshot) }
        $ui.Insights.Text = ((@(Get-PCMeasuredInsights $script:chartFrames) + $base) -join "`n`n")
    }
    function Show-Error($err) {
        $ui.Status.Text = 'Action could not be completed.'; $ui.ProgressLabel.Text = 'Test unavailable or failed — see error details'
        [Windows.MessageBox]::Show([string]$err, 'PC Insight', 'OK', 'Error') | Out-Null
    }
    function Confirm($message) { [Windows.MessageBox]::Show($message, 'Review change', 'YesNo', 'Question') -eq 'Yes' }
    function Set-Busy($busy) {
        if($busy -and $script:overlayWindow -and $script:overlayWindow.IsVisible){Hide-PCGameOverlay 'Overlay paused for the app task. Use the hotkey to resume after it finishes.'}
        foreach ($n in 'CheckUpdate','ReopenAdmin','Scan','Benchmark','PlansRefresh','Apply','Restore','Export','SensorStart','MultiBenchmark','DashboardTest','DashboardRecord','MonitorStart','LongCPU','MemoryTest','GPUTest','DetectTuning','ApplyGPU','RestoreGPU','SaveBaseline','CompareBaseline','RepeatCPU','RepeatRAM','RepeatGPU','SaveProfile','LoadProfile') { $ui[$n].IsEnabled = -not $busy }
        if (-not $busy) { $ui.DashboardTest.IsEnabled = $null -ne $script:snapshot; $ui.Benchmark.IsEnabled = $null -ne $script:snapshot; $ui.MultiBenchmark.IsEnabled = $null -ne $script:snapshot; $ui.Export.IsEnabled = $null -ne $script:snapshot }
        if (-not $busy) { foreach ($n in 'LongCPU','MemoryTest','GPUTest','RepeatCPU','RepeatRAM','RepeatGPU','SaveProfile','LoadProfile') { $ui[$n].IsEnabled = $null -ne $script:snapshot } }
        if (-not $busy) { $ui.SaveBaseline.IsEnabled = $null -ne $script:snapshot }
        $ui.TestProgress.IsIndeterminate = $busy -and $script:jobKind -in @('scan','monitor')
        $ui.MonitorStop.IsEnabled = $busy -and $script:jobKind -eq 'monitor'
        $ui.Cancel.IsEnabled = $busy
        $ui.SensorCancel.IsEnabled = $busy
        $ui.ExportSessionCsv.IsEnabled = -not $busy -and $null -ne $ui.SessionPicker.SelectedItem
        $ui.ExportSessionJson.IsEnabled = -not $busy -and $null -ne $ui.SessionPicker.SelectedItem
        Update-PCComparisonExportState
        $ui.UpdateFeed.IsEnabled = -not $busy
        $ui.DownloadUpdate.IsEnabled = -not $busy -and $null -ne $script:updateRelease
        $ui.InstallUpdate.IsEnabled = -not $busy -and $null -ne $script:updateSource
        if(Get-Command Refresh-GuideUI -ErrorAction SilentlyContinue){Refresh-GuideUI}
        if(Get-Command Update-PCClockControlState -ErrorAction SilentlyContinue){Update-PCClockControlState $busy}
        if(Get-Command Refresh-PCClockGuideUI -ErrorAction SilentlyContinue){Refresh-PCClockGuideUI}
        if(Get-Command Refresh-PCGpuEnduranceUI -ErrorAction SilentlyContinue){Refresh-PCGpuEnduranceUI}
    }
    function Format-Snapshot($s) {
        $out = [System.Collections.Generic.List[string]]::new()
        foreach ($c in $s.CPU) {
            $load = 'unavailable'; if ($null -ne $c.LoadPercentage) { $load = "$($c.LoadPercentage)%" }
            $out.Add("CPU  $($c.Name)`n$($c.NumberOfCores) cores / $($c.NumberOfLogicalProcessors) logical processors | Snapshot load: $load`n")
        }
        if ($null -ne $s.MemoryTotalGiB) { $out.Add("MEMORY  $($s.MemoryTotalGiB) GiB usable / $($s.MemoryFreeGiB) GiB free`n") } else { $out.Add("MEMORY  Reading unavailable`n") }
        foreach ($r in $s.RAM) { $out.Add("  $($r.DeviceLocator): $([math]::Round($r.Capacity / 1GB, 1)) GiB | Firmware configured speed: $($r.ConfiguredClockSpeed)") }
        foreach ($g in $s.GPU) { $out.Add("`nGPU  $($g.Name)`nDriver: $($g.DriverVersion)") }
        foreach ($g in $s.GPUTelemetry) { $out.Add("  $($g.Name): $($g.Utilization)% load | $($g.Temperature) C | $($g.Power) W | $($g.MemoryMiB) MiB VRAM") }
        foreach ($b in $s.Board) { $out.Add("`nMOTHERBOARD  $($b.Manufacturer) $($b.Product)") }
        foreach ($b in $s.BIOS) { $out.Add("BIOS  $($b.SMBIOSBIOSVersion)") }
        foreach ($d in $s.Disks) { $out.Add("`nSTORAGE  $($d.DeviceID)  $([math]::Round($d.FreeSpace / 1GB, 1)) GiB free / $([math]::Round($d.Size / 1GB, 1)) GiB") }
        $out.Add("`nCPU temperatures and reported clocks: see Live sensors. Effective clocks and throttling diagnosis are not established.`nGPU readings absent? That vendor sensor is unavailable in this preview.")
        foreach ($w in $s.Warnings) { $out.Add("`nCollection warning: $w") }
        $out -join "`n"
    }
    function Show-History {
        $rows = @($script:history)
        if ($rows.Count -eq 0) { return }
        $texts = @($rows | Select-Object -Last 30 | ForEach-Object { "$($_.Timestamp)`n$(Format-PCValue (Get-PCResultRate $_) (Get-PCResultUnit $_)) | $($_.Test)`nCPU: $($_.CPUName)`nPower plan: $($_.Plan)`n" })
        $summary = Get-PCComparison $rows[-1] $rows
        $ui.BatchReport.Text = Get-PCBatchReport $script:history
        $ui.Results.Text = $summary + "`n`n" + ($texts -join "`n")
    }
    if (Test-Path $historyPath) {
        try { $script:history = @(Expand-PCHistory (Get-Content $historyPath -Raw | ConvertFrom-Json)); Show-History }
        catch { $ui.Status.Text = 'Saved history could not be read. Existing file retained until a new result is saved.' }
    }
    $sessionPath = Join-Path $dataDir 'sessions.json'
    if (Test-Path $sessionPath) {
        try { $script:sessions = @(Expand-PCHistory (Get-Content $sessionPath -Raw | ConvertFrom-Json)) }
        catch { $ui.Status.Text = 'Previous sensor sessions could not be read.' }
    }
    $ui.SessionResults.Text = Get-PCSessionSummary ($script:sessions | Select-Object -Last 1) $script:history
    Show-DashboardResult
    if (Test-Path $restorePath) { $ui.PowerStatus.Text = 'A previous plan is saved. Use Restore previous plan to recover it.' }
    function Start-Task($kind) {
        if ($script:job -or $script:updateJob) { return }
        if((Get-Command Test-PCClockGuideLocked -ErrorAction SilentlyContinue) -and (Test-PCClockGuideLocked) -and -not $script:clockGuideRun){return}
        if ($kind -in @('sensors','multicore','monitor','longcpu','memory','gpu','repeatcpu','repeatram','repeatgpu','endurance5','endurance10')) { $script:chartFrames = @(); $ui.TemperatureChart.Children.Clear(); $ui.UsageChart.Children.Clear() }
        Remove-Item -LiteralPath $script:stopPath -ErrorAction SilentlyContinue
        $script:lastFrameTime = Get-Date
        $ui.TestProgress.Value = 0; $ui.ProgressLabel.Text = 'Preparing ' + $kind
        $script:jobKind = $kind
        $script:taskStarted = Get-Date
        $script:pendingResult = $null
        Set-Busy $true
        $script:testPowerState=$null
        if ($kind -in @('benchmark','multicore','longcpu','memory','gpu','repeatcpu','repeatram','repeatgpu','endurance5','endurance10')) { $script:testPowerState=Get-PCTuningCapabilities }
        $ui.Status.Text = if ($kind -eq 'scan') { 'Reading hardware. This can take up to a minute...' } elseif ($kind -eq 'monitor') { 'Live monitoring active. Use Stop and save when finished.' } elseif ($kind -eq 'longcpu') { 'Running 60-second monitored CPU test...' } elseif ($kind -eq 'gpu') { 'GPU: 5-second warm-up, then 30-second measurement...' } elseif ($kind -eq 'memory') { 'Preparing 20-second memory test...' } elseif ($kind -like 'endurance*') { 'Preparing GPU endurance test...' }
                        elseif ($kind -like 'repeat*') { 'Starting a three-run batch with 10-second cooldowns...' } elseif ($kind -eq 'benchmark') { 'Running 15-second single-worker CPU test...' } else { 'Recording sensors for 20 seconds...' }
        try {
            $script:job = Start-Job -ArgumentList "$PSScriptRoot\Engine.ps1",$kind,$script:SensorLogPath,$script:stopPath -ScriptBlock {
                param($engine,$kind,$logPath,$stopPath)
                $ErrorActionPreference = 'Stop'
                . $engine
                . (Join-Path (Split-Path $engine) 'Monitor.ps1')
                . (Join-Path (Split-Path $engine) 'LiveMonitor.ps1')
                . (Join-Path (Split-Path $engine) 'ExtendedTests.ps1')
                . (Join-Path (Split-Path $engine) 'GpuEndurance.ps1')
                . (Join-Path (Split-Path $engine) 'Power.ps1')
                . (Join-Path (Split-Path $engine) 'Tuning.ps1')
                . (Join-Path (Split-Path $engine) 'RepeatedTests.ps1')
                . (Join-Path (Split-Path $engine) 'LogSensors.ps1')
                $script:SensorLogPath = $logPath
                . (Join-Path (Split-Path $engine) 'NativeSensors.ps1')
                try {
                    if ($kind -eq 'scan') { Get-PCSnapshot }
                    elseif ($kind -eq 'benchmark') { Invoke-PCBenchmark }
                    else {
                        Initialize-PCNativeSensors
                        if ($kind -eq 'monitor') { Invoke-PCContinuousSession -StopPath $stopPath }
                        elseif ($kind -like 'endurance*') { $duration=if($kind -eq 'endurance5'){300}else{600}; Invoke-PCGpuEndurance -DurationSeconds $duration -StopPath $stopPath }
                        elseif ($kind -like 'repeat*') { $type=switch($kind){'repeatcpu'{'longcpu'} 'repeatram'{'memory'} 'repeatgpu'{'gpu'}}; Invoke-PCRepeatedTest $type }
                        elseif ($kind -eq 'longcpu') { Invoke-PCSensorSession -WithLoad -DurationSeconds 60 }
                        elseif ($kind -in @('memory','gpu')) { Invoke-PCExtendedTest -Kind $kind }
                        elseif ($kind -eq 'multicore') { Invoke-PCSensorSession -WithLoad }
                        else { Invoke-PCSensorSession }
                    }
                } finally { Close-PCNativeSensors }
            }
        } catch { Set-Busy $false; Show-Error $_.Exception.Message }
    }
    $ui.MonitorStart.Add_Click({ Start-Task 'monitor' })
    $ui.MonitorStop.Add_Click({
        try { Set-Content -LiteralPath $script:stopPath -Value 'stop'; $ui.MonitorStop.IsEnabled = $false; $ui.Status.Text = 'Stopping monitoring and saving the latest 300 samples...' } catch { Show-Error $_.Exception.Message }
    })
    $ui.Scan.Add_Click({ Start-Task 'scan' })
    $ui.Benchmark.Add_Click({
        if (Confirm 'Run a 15-second CPU workload? Save your work first. This creates CPU load and may increase heat and fan noise. CPU temperature monitoring is unavailable. Cancel stops the test; no settings are changed.') {
            try { $script:testPlan = Get-ActivePlan; Start-Task 'benchmark' } catch { Show-Error $_.Exception.Message }
        }
    })
    $ui.SensorStart.Add_Click({ Start-Task 'sensors' })

    $ui.MultiBenchmark.Add_Click({
        if (Confirm 'Run a 20-second parallel CPU test with up to 16 workers? Save your work. A CPU temperature reading is required. The test stops if a reading is missing, a query is slow, or a reported CPU temperature reaches 85 C. Provider readings may be cached; this is not a guaranteed thermal safeguard or a stability test. No hardware settings will be changed.') {
            try { $script:testPlan = Get-ActivePlan; Start-Task 'multicore' } catch { Show-Error $_.Exception.Message }
        }
    })
    # Each click explicitly starts the labelled test; no extra confirmation dialog.
    $ui.LongCPU.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'longcpu' } catch { Show-Error $_.Exception.Message } })
    $ui.MemoryTest.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'memory' } catch { Show-Error $_.Exception.Message } })
    $ui.GPUTest.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'gpu' } catch { Show-Error $_.Exception.Message } })
    $ui.RepeatCPU.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'repeatcpu' } catch { Show-Error $_.Exception.Message } })
    $ui.RepeatRAM.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'repeatram' } catch { Show-Error $_.Exception.Message } })
    $ui.RepeatGPU.Add_Click({ try { $script:testPlan=Get-ActivePlan; Start-Task 'repeatgpu' } catch { Show-Error $_.Exception.Message } })
    $ui.DashboardRecord.Add_Click({ Start-Task 'sensors' })
    $ui.OpenResults.Add_Click({ $ui.Navigation.SelectedIndex = 4 })
    $ui.DashboardTest.Add_Click({ $ui.MultiBenchmark.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) })
    function Show-SensorFrame($frame) {
        $ui.CPUReadingTime.Text = 'Sampled ' + ([datetimeoffset]::Parse([string]$frame.Timestamp)).ToLocalTime().ToString('HH:mm:ss')
        $cpuLoad = $frame.Sensors | Where-Object { $_.Type -eq 'Load' -and $_.Name -eq 'CPU Total' -and $_.Parent -match '^/(intelcpu|amdcpu)/' } | Select-Object -First 1
        $gpuLoad = $frame.Sensors | Where-Object { $_.Type -eq 'Load' -and $_.Name -eq 'GPU Core' -and $_.Parent -match '^/gpu' } | Select-Object -First 1
        $ui.GPUReadingTime.Text = $ui.CPUReadingTime.Text + ' · Load ' + (Format-PCValue $gpuLoad.Value '%')
        $p = $frame.Sensors | Where-Object { $_.Parent -match '^/(intelcpu|amdcpu)/' -and $_.Type -eq 'Power' -and $_.Name -eq 'CPU Package' } | Select-Object -First 1
        $ui.CPUPower.Text = 'Package power · ' + (Format-PCValue $p.Value 'W') + ' · CPU load ' + (Format-PCValue $cpuLoad.Value '%')
        $ui.CPUTemp.Text = Format-PCValue $frame.CPUCelsius '°C'
        $g = @($frame.Sensors | Where-Object { $_.Parent -match '^/gpu' -and $_.Name -eq 'GPU Core' -and $_.Type -eq 'Temperature' } | Select-Object -First 1)
        $ui.GPUTemp.Text = if ($g.Count) { Format-PCValue $g[0].Value '°C' } else { 'Unavailable' }
        $script:lastFrameTime = Get-Date
        if ($null -ne $frame.MemoryUsedPercent) { $ui.RAMUsed.Text = Format-PCValue $frame.MemoryUsedPercent '%'; $ui.RAMSampleLabel.Text = $ui.CPUReadingTime.Text }
        elseif ($script:jobKind -eq 'monitor') { $ui.RAMUsed.Text = 'Unavailable'; $ui.RAMSampleLabel.Text = 'Memory query unavailable' }
        $script:chartFrames = @((@($script:chartFrames) + @($frame)) | Select-Object -Last 300)
        Show-Chart $script:chartFrames
        Show-MeasuredInsights
        $lines = @($frame.Sensors | ForEach-Object { '{0}: {1:N1} [{2}]  {3}' -f $_.Name,$_.Value,$_.Type,$_.Parent })
        $ui.SensorReadings.Text = ($lines -join "`n")
        if ($frame.Issue) { $ui.SensorReadings.Text = ($lines -join "`n") + "`n`n" + $frame.Issue + "`n`nBuilt-in sensor access needs compatible hardware and drivers. If running with standard access, finish or stop this session, then choose Reopen as administrator. See README for the PawnIO dependency." }
        $temp = 'unavailable'; if ($null -ne $frame.CPUCelsius) { $temp = "$($frame.CPUCelsius) C" }
        $freshness = 'Direct update requested; sensor age not supplied'
        if ($null -ne $frame.SampleAgeSeconds) { $freshness = "Log sample age: $($frame.SampleAgeSeconds) seconds" }
        $ui.SensorSummary.Text = "Query: $($frame.Timestamp) | CPU: $temp | $freshness | $($frame.Provider)"
    }
    function Cancel-Task([switch]$Force) {
        if($script:job -and $script:jobKind -like 'endurance*'){
            if(-not $Force){
                Set-Content -LiteralPath $script:stopPath -Value 'stop'
                Save-PCGpuEnduranceStatus 'Stopping' 'Stopping GPU load; partial result will be saved when the worker responds.'
                return
            }
            Save-PCGpuEnduranceStatus 'Interrupted' 'Endurance test interrupted by close, timeout or unresponsive worker. No completed result was saved. Check Tuning to restore any saved offsets.'
        }
        if ($script:job) {
            Stop-Job $script:job -ErrorAction SilentlyContinue
            Remove-Job $script:job -Force -ErrorAction SilentlyContinue
            $script:job = $null; Set-Busy $false; $ui.Status.Text = 'Task cancelled. No result was saved.'; $ui.ProgressLabel.Text = 'Cancelled'; $ui.TestProgress.Value=0
        }
        if($script:guideRun){Interrupt-GuideRun 'Guided test cancelled or timed out.'}
        if($script:clockGuideRun){Interrupt-PCClockGuide 'Core trial cancelled or timed out.'}
    }
    $ui.Cancel.Add_Click({ Cancel-Task })
    $ui.SensorCancel.Add_Click({ Cancel-Task })
    $script:timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $timer.Add_Tick({
        if (-not $script:job) { return }
        if ($script:jobKind -eq 'monitor' -and ((Get-Date) - $script:lastFrameTime).TotalSeconds -gt 30) { Cancel-Task; $ui.Status.Text = 'Monitoring stopped: no sensor response for 30 seconds. No session was saved.'; return }
        if ($script:jobKind -like 'endurance*' -and ((Get-Date)-$script:lastFrameTime).TotalSeconds -gt 30) { Cancel-Task -Force; $ui.Status.Text='GPU endurance stopped: no sensor response for 30 seconds.'; return }
        if ($script:jobKind -ne 'monitor' -and ((Get-Date) - $script:taskStarted).TotalSeconds -gt $(if($script:jobKind -eq 'endurance5'){360}elseif($script:jobKind -eq 'endurance10'){660}elseif($script:jobKind -like 'repeat*'){360}else{100})) { Cancel-Task -Force; $ui.Status.Text = 'Task timed out. Try again or inspect Windows management services.'; return }
        $finish = $false
        $guideCompleted=$null;$clockGuideCompleted=$null
        $terminal = $script:job.State -in @('Completed','Failed','Stopped')
        try {
            $incoming = @(Receive-Job $script:job -ErrorAction Stop)
            foreach ($item in $incoming) {
                if ($script:jobKind -in @('sensors','multicore','monitor','longcpu','memory','gpu','repeatcpu','repeatram','repeatgpu','endurance5','endurance10')) {
                    if ($item.Kind -eq 'Frame') { Show-SensorFrame $item.Value }
                    elseif ($item.Kind -eq 'EnduranceProgress') { $ui.EnduranceStatus.Text=$item.Value; $ui.ProgressLabel.Text=$item.Value }
                    elseif ($item.Kind -eq 'Phase') { $ui.ProgressLabel.Text = $script:jobKind + ': ' + $item.Value }
                    elseif ($item.Kind -eq 'BatchStatus') { $ui.Status.Text=$item.Value; $script:chartFrames=@() }
                    elseif ($item.Kind -eq 'Progress') { $ui.TestProgress.Value = $item.Value; $ui.ProgressLabel.Text = ('{0}: {1:N0}% of measurement interval' -f $script:jobKind,$item.Value) }
                    elseif ($item.Kind -eq 'Result') { $script:pendingResult = $item.Value }
                } else { $script:pendingResult = $item }
            }
            if (-not $terminal) { return }
            $finish = $true
            if ($script:job.State -ne 'Completed') { throw 'Background task failed. No result was saved.' }
            $value = $script:pendingResult
            if ($null -eq $value) { throw 'No measurement was returned.' }
            $values=@($value); if($value.BatchResults){$values=@($value.BatchResults)}
            foreach($value in $values){
            if ($script:jobKind -eq 'scan') {
                $script:snapshot = $value
                $c = $value.CPU | Select-Object -First 1
                $ui.CPUDetails.Text = if ($c) { "$($c.NumberOfCores) cores / $($c.NumberOfLogicalProcessors) threads" } else { 'Processor details unavailable' }
                $ui.CPUModel.Text = ($value.CPU.Name -join '; ')
                $ui.GPUModel.Text = ($value.GPU.Name -join '; ')
                $ui.RAMModel.Text = Format-PCValue $value.MemoryTotalGiB 'GiB usable'
                $ui.RAMUsed.Text = Format-PCValue $value.MemoryUsedPercent '%'
                $ui.Overview.Text = Format-Snapshot $value
                $ui.RAMSampleLabel.Text = 'Memory used at scan time'
                Show-MeasuredInsights
                $ui.ScanTime.Text = 'Snapshot: ' + (Get-Date).ToString('HH:mm:ss')
                $ui.Status.Text = 'Scan complete. Open Insights for findings.'
            } elseif ($script:jobKind -in @('sensors','multicore','monitor','longcpu','memory','gpu','repeatcpu','repeatram','repeatgpu','endurance5','endurance10')) {
                $value | Add-Member -NotePropertyName CPUName -NotePropertyValue (($script:snapshot.CPU.Name) -join '; ')
                if(-not $value.PSObject.Properties['Plan']) { $value | Add-Member -NotePropertyName Plan -NotePropertyValue $(if ($script:jobKind -in @('multicore','longcpu','memory','gpu','repeatcpu','repeatram','repeatgpu','endurance5','endurance10')) { $script:testPlan } else { $null }) }
                if(-not $value.PSObject.Properties['PowerStateAtStart']) { $value | Add-Member -NotePropertyName PowerStateAtStart -NotePropertyValue $script:testPowerState }
                $value | Add-Member -NotePropertyName DriverVersion -NotePropertyValue (($script:snapshot.GPU.DriverVersion) -join '; ')
                $value | Add-Member -NotePropertyName MemoryConfig -NotePropertyValue (($script:snapshot.RAM | ForEach-Object { "$($_.Capacity):$($_.ConfiguredClockSpeed)" }) -join ';')
                $script:sessions = @($script:sessions) + @($value)
                $script:sessions = @($script:sessions | Select-Object -Last 10)
                Save-JsonAtomic $script:sessions (Join-Path $dataDir 'sessions.json')
                $summary = "Recorded $($value.Frames.Count) sensor queries. Peak CPU: $($value.PeakCPU) C."
                if ($null -eq $value.PeakCPU) { $summary = 'Recording completed without CPU temperatures. Check sensor setup.' }
                if ($value.StopReason) { $summary = 'Test stopped: ' + $value.StopReason + ' No comparable score was recorded.' }
                elseif ($null -ne (Get-PCResultRate $value)) { $summary += " Throughput: $(Format-PCValue (Get-PCResultRate $value) (Get-PCResultUnit $value))." }
                if($value.EnduranceOutcome){$summary=$value.EnduranceOutcome+' GPU peak: '+(Format-PCValue $value.PeakGPU 'C');Save-PCGpuEnduranceStatus $(if($value.Completed){'Completed'}else{'Stopped'}) $summary}
                $ui.SensorSummary.Text = $summary
                $ui.Status.Text = $summary
                if ($null -ne (Get-PCResultRate $value)) {
                    $score = $value | Select-Object Test,BatchId,RunIndex,RunCount,Timestamp,Seconds,PowerStateAtStart,MiBPerSecond,GpuFramesPerSecond,GPUName,Renderer,BufferMiB,DriverVersion,MemoryConfig,Workers,Runtime,Completed,StopReason,PeakCPU,CPUName,Plan
                    $script:history = @($script:history) + @($score)
                    Save-JsonAtomic @($script:history | Select-Object -Last 100) $historyPath
                    Show-History
                }
                $ui.SessionResults.Text = Get-PCSessionSummary $value $script:history
                Show-DashboardResult
                $ui.BaselineResult.Text=Get-PCBaselineComparison $script:baseline $script:history $script:sessions
                $ui.TestProgress.Value=100; $ui.ProgressLabel.Text=if($value.StopReason){'Stopped: '+$value.StopReason}else{'Session completed — open Test results'}
            } else {
                $value | Add-Member -NotePropertyName CPUName -NotePropertyValue (($script:snapshot.CPU.Name) -join '; ')
                $value | Add-Member -NotePropertyName Plan -NotePropertyValue $script:testPlan
                $script:history = @($script:history) + @($value)
                Save-JsonAtomic @($script:history | Select-Object -Last 100) $historyPath
                Show-History
                if(-not $value.PSObject.Properties['PowerStateAtStart']) { $value | Add-Member -NotePropertyName PowerStateAtStart -NotePropertyValue $script:testPowerState -Force }
                $ui.Status.Text = 'CPU test complete. A short benchmark does not establish stability.'
            }
            }
            if($script:guideRun){$guideCompleted=@($values)}
            if($script:clockGuideRun){$clockGuideCompleted=@($values)}
        } catch {
            $finish = $true
            if($script:jobKind -like 'endurance*'){Save-PCGpuEnduranceStatus 'Interrupted' ('Endurance worker failed: '+$_.Exception.Message)}
            Stop-Job $script:job -ErrorAction SilentlyContinue
            if($script:guideRun){Interrupt-GuideRun $_.Exception.Message}
            if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message}
            Show-Error $_.Exception.Message
        } finally {
            if ($script:job -and $finish) {
                Remove-Job $script:job -Force -ErrorAction SilentlyContinue; $script:job = $null; Set-Busy $false
            }
            if($null -ne $guideCompleted -and $script:guideRun){Complete-GuideRun $guideCompleted}
            if($null -ne $clockGuideCompleted -and $script:clockGuideRun){Complete-PCClockGuideRun $clockGuideCompleted}
        }
    })
    $timer.Start()
    $ui.PlansRefresh.Add_Click({
        try { $ui.Plans.ItemsSource = @(Get-AvailablePlans); $ui.PowerStatus.Text = 'Active plan: ' + (Get-ActivePlan) } catch { Show-Error $_.Exception.Message }
    })
    $ui.Apply.Add_Click({
        try {
            $plan = $ui.Plans.SelectedItem
            if (-not $plan) { throw 'Load installed plans, then select one.' }
            $current = Get-ActivePlan
            if ($current -eq $plan.ID) { $ui.PowerStatus.Text = 'That plan is already active.'; return }
            if (-not (Confirm "Switch to '$($plan.Name)'? This may change heat, battery life, responsiveness and sleep behaviour. It does not overclock the PC. Your original plan is saved before applying. The change persists when the app closes. Use Restore previous plan to undo it.")) { return }
            if (-not (Test-Path $restorePath)) {
                Save-JsonAtomic ([pscustomobject]@{ OriginalPlan = $current; Created = (Get-Date).ToString('o') }) $restorePath
            } else {
                # Refuse to change anything if recovery data is damaged.
                $saved = Get-Content $restorePath -Raw | ConvertFrom-Json
                if ($saved.OriginalPlan -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') { throw 'Recovery file is invalid. Resolve it before making another change.' }
            }
            Set-VerifiedPlan $plan.ID
            $ui.PowerStatus.Text = "Applied and verified: $($plan.Name). Run the CPU test again to compare."
        } catch { Show-Error $_.Exception.Message }
    })
    $ui.Restore.Add_Click({
        try {
            if (-not (Test-Path $restorePath)) { throw 'There is no saved power-plan change to restore.' }
            $saved = Get-Content $restorePath -Raw | ConvertFrom-Json
            if (-not (Confirm "Restore the saved original power plan ($($saved.OriginalPlan))?")) { return }
            Set-VerifiedPlan $saved.OriginalPlan
            Remove-Item -LiteralPath $restorePath -ErrorAction Stop
            $ui.PowerStatus.Text = 'Original plan restored and verified.'
        } catch { Show-Error $_.Exception.Message }
    })
    function New-TuningBaseline {
        [pscustomobject]@{Schema=1;Created=(Get-Date).ToString('o');Snapshot=$script:snapshot;Capabilities=$script:capabilities;PowerPlan=(Get-ActivePlan);Benchmarks=@($script:history);Sessions=@($script:sessions)}
    }
    function Refresh-Tuning {
        $script:capabilities=Get-PCTuningCapabilities
        $ui.GPUDevice.ItemsSource=@($script:capabilities.Devices)
        if($script:capabilities.Devices.Count -gt 0){$ui.GPUDevice.SelectedIndex=0}
        $lines=@($script:capabilities.CPU,$script:capabilities.GPU,$script:capabilities.RAM)
        if($script:capabilities.Issue){$lines += $script:capabilities.Issue}
        foreach($d in $script:capabilities.Devices){$lines += "$($d.Name): current $($d.Current) W / default $($d.Default) W / range $($d.Min)–$($d.Max) W. $($d.Status)"}
        $ui.CapabilityText.Text=$lines -join "`n`n"
    }
    $ui.DetectTuning.Add_Click({ try { Set-Busy $true; Refresh-Tuning } catch { Show-Error $_.Exception.Message } finally { Set-Busy $false } })
    $ui.SaveBaseline.Add_Click({
        try {
            if(Test-Path $script:gpuJournalPath){throw 'Restore the saved GPU limit before replacing the original baseline.'}
            Set-Busy $true; Refresh-Tuning
            $script:baseline=New-TuningBaseline
            if(Test-Path $script:baselinePath){Copy-Item $script:baselinePath ($script:baselinePath+'.previous') -Force}
            Save-JsonAtomic $script:baseline $script:baselinePath
            $ui.BaselineResult.Text=Get-PCBaselineComparison $script:baseline $script:history $script:sessions
        }catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}
    })
    $ui.CompareBaseline.Add_Click({$ui.BaselineResult.Text=Get-PCBaselineComparison $script:baseline $script:history $script:sessions})
    $ui.ApplyGPU.Add_Click({
        try {
            if(-not $script:snapshot){throw 'Scan this PC first.'}
            $selected=$ui.GPUDevice.SelectedItem
            if(-not $selected -or -not $selected.Available){throw 'Detect compatibility and select a GPU with reported power limits.'}
            $percent=[int]$ui.PowerPreset.SelectedItem.Tag
            $original=$selected.Current
            if(Test-Path $script:gpuJournalPath){$original=(Read-PCPowerJournal $script:gpuJournalPath).OriginalWatts}
            $target=[math]::Round($original*$percent/100,2)
            if(-not (Confirm "Apply $target W to $($selected.Name)? Current reported limit: $($selected.Current) W. GPU: $($selected.UUID). This may reduce performance, heat and power consumption. Original settings and a baseline are saved before the change. Closing the app does not restore the limit. Use Restore saved GPU limit to undo it. No clocks or voltages will be written.")){return}
            Set-Busy $true
            $baseline=New-TuningBaseline
            $ui.TuningStatus.Text=Set-PCPowerReduction $selected $percent $script:gpuJournalPath $script:baselinePath $baseline
            $script:baseline=Get-Content $script:baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
            Refresh-Tuning
        }catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}
    })
    $ui.RestoreGPU.Add_Click({
        try {
            $j=Read-PCPowerJournal $script:gpuJournalPath
            if(-not (Confirm "Restore the saved $($j.OriginalWatts) W limit for $($j.Name), GPU $($j.UUID)?")){return}
            Set-Busy $true
            $ui.TuningStatus.Text=Restore-PCPower $script:gpuJournalPath
            Refresh-Tuning
        }catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}
    })
    function Refresh-Profiles {
        $ui.ProfilePicker.ItemsSource=@(Get-PCNamedProfiles $script:profilesPath | Sort-Object Saved -Descending)
        if($ui.ProfilePicker.Items.Count){$ui.ProfilePicker.SelectedIndex=0}
    }
    Refresh-Profiles
    $ui.SaveProfile.Add_Click({
        try {
            $saved=Save-PCNamedProfile $script:profilesPath $ui.ProfileName.Text $script:baseline
            Refresh-Profiles
            $ui.ProfileStatus.Text="Saved '$($saved.Name)' as an independent copy of the active baseline. Hardware settings were not changed."
        }catch{Show-Error $_.Exception.Message}
    })
    $ui.LoadProfile.Add_Click({
        try {
            if(Test-Path $script:gpuJournalPath){throw 'Restore the saved GPU limit before switching comparison baselines.'}
            $selected=$ui.ProfilePicker.SelectedItem
            if(-not $selected){throw 'Select a named profile first.'}
            $profile=Read-PCNamedProfile $script:profilesPath $selected.ID
            $script:baseline=$profile.Baseline
            Save-JsonAtomic $script:baseline $script:baselinePath
            $ui.BaselineResult.Text=Get-PCBaselineComparison $script:baseline $script:history $script:sessions
            $ui.ProfileStatus.Text="Loaded '$($profile.Name)' for comparison only. No hardware settings were applied."
        }catch{Show-Error $_.Exception.Message}
    })
    $ui.Export.Add_Click({
        try {
            $dialog = [Microsoft.Win32.SaveFileDialog]::new(); $dialog.Filter = 'JSON report (*.json)|*.json'; $dialog.FileName = 'PC-Insight-report.json'
            if ($dialog.ShowDialog() -eq $true) {
                $report = [pscustomobject]@{ AppVersion = $script:appVersion; GuidedOptimization = $script:guide; AdministratorAccess = $script:isAdministrator; LatestSessionSummary = (Get-PCSessionSummary ($script:sessions | Select-Object -Last 1) $script:history); RepeatedTestSummary = (Get-PCBatchReport $script:history); TuningCapabilities = $script:capabilities; BaselineComparison = (Get-PCBaselineComparison $script:baseline $script:history $script:sessions); GPURecoveryPending = (Test-Path $script:gpuJournalPath); Snapshot = $script:snapshot; Insights = @(Get-PCInsights $script:snapshot); MeasuredInsights = @(Get-PCMeasuredInsights $script:chartFrames); Benchmarks = @($script:history); SensorSessions = @($script:sessions) }
                Save-JsonAtomic $report $dialog.FileName
                $ui.Status.Text = 'Report exported. Review hardware details before sharing.'
            }
        } catch { Show-Error $_.Exception.Message }
    })

    $script:updateJob=$null; $script:updateRelease=$null; $script:updateSource=$null
    $script:updateConfig=Join-Path $dataDir 'update-feed.json'
    $ui.UpdateFeed.Text='https://github.com/IGN1TE/pc-insight/releases/latest/download/update.json'
    $ui.UpdateStatus.Text='GitHub release feed ready. Choose Save feed and check to look for updates.'
    if(Test-Path $script:updateConfig){
        try{$ui.UpdateFeed.Text=[string](Get-Content $script:updateConfig -Raw|ConvertFrom-Json).Url;$ui.UpdateStatus.Text='Release feed saved. Choose Save feed and check to look for updates.'}catch{$ui.UpdateStatus.Text='Saved feed could not be read. Enter a trusted release URL.'}
    }
    function Start-UpdateTask([string]$kind,$argument) {
        if($script:job -or $script:updateJob){return}
        $script:updateKind=$kind; $script:jobKind='update'
        Set-Busy $true; $ui.Cancel.IsEnabled=$false; $ui.SensorCancel.IsEnabled=$false; $ui.CancelUpdate.IsEnabled=$true
        $ui.UpdateStatus.Text=if($kind -eq 'check'){'Checking release feed...'}else{'Downloading and verifying update...'}
        try {
            $script:updateStarted=Get-Date
            $script:updateJob=Start-Job -ArgumentList $PSScriptRoot,$kind,$argument,$dataDir -ScriptBlock {
                param($root,$kind,$argument,$data)
                $ErrorActionPreference='Stop'; . (Join-Path $root 'Updates.ps1')
                if($kind -eq 'check'){Get-PCUpdate $argument (Get-PCAppVersion)}else{Save-PCUpdate $argument (Join-Path $data 'updates')}
            }
        } catch {Set-Busy $false; $ui.CancelUpdate.IsEnabled=$false; Show-Error $_.Exception.Message}
    }
    $ui.CheckUpdate.Add_Click({
        try {
            $url=Assert-PCUpdateUrl $ui.UpdateFeed.Text.Trim()
            Save-JsonAtomic ([pscustomobject]@{Url=$url}) $script:updateConfig
            $script:updateRelease=$null; $script:updateSource=$null
            $ui.ReleaseNotes.Text='Checking for release notes...'
            Start-UpdateTask 'check' $url
        }catch{Show-Error $_.Exception.Message}
    })
    $ui.UpdateFeed.Add_TextChanged({
        $script:updateRelease=$null; $script:updateSource=$null
        $ui.DownloadUpdate.IsEnabled=$false; $ui.InstallUpdate.IsEnabled=$false
        $ui.ReleaseNotes.Text='Check this feed to load release notes.'
        $ui.LastUpdateCheck.Text='This feed has not been checked in this session.'
    })
    $ui.DownloadUpdate.Add_Click({if($script:updateRelease){Start-UpdateTask 'download' $script:updateRelease}})
    function Stop-UpdateTask {
        if($script:updateJob){Stop-Job $script:updateJob -ErrorAction SilentlyContinue;Remove-Job $script:updateJob -Force -ErrorAction SilentlyContinue;$script:updateJob=$null}
        Set-Busy $false; $ui.CancelUpdate.IsEnabled=$false
    }
    $ui.CancelUpdate.Add_Click({Stop-UpdateTask;$ui.UpdateStatus.Text='Update task cancelled. Nothing was installed.'})
    $script:updateTimer=[Windows.Threading.DispatcherTimer]::new()
    $updateTimer.Interval=[TimeSpan]::FromMilliseconds(500)
    $updateTimer.Add_Tick({
        if(-not $script:updateJob){return}
        if(((Get-Date)-$script:updateStarted).TotalSeconds -gt 300){Stop-UpdateTask;$ui.UpdateStatus.Text='Update task timed out. Nothing was installed.';return}
        if($script:updateJob.State -notin @('Completed','Failed','Stopped')){return}
        try {
            $result=@(Receive-Job $script:updateJob -ErrorAction Stop)
            if($script:updateJob.State -ne 'Completed' -or $result.Count -ne 1){throw 'Update task failed to return a valid result.'}
            if($script:updateKind -eq 'check'){
                $ui.LastUpdateCheck.Text='Last successful check: '+(Get-Date).ToString('g')
                $ui.ReleaseNotes.Text=if([string]::IsNullOrWhiteSpace([string]$result[0].ReleaseNotes)){'This release does not include notes in its update feed.'}else{[string]$result[0].ReleaseNotes}
                if($result[0].Available){$script:updateRelease=$result[0];$ui.UpdateStatus.Text=('Version {0} is available ({1:N1} MiB). Review the notes, then choose Download update.' -f $result[0].Version,($result[0].SizeBytes/1MB))}
                else{$ui.UpdateStatus.Text='No newer release is available from this feed.'}
            }else{$script:updateSource=[string]$result[0];$ui.UpdateStatus.Text='Package verified and ready. Install and restart will close this window and update the installed app.'}
        }catch{$ui.UpdateStatus.Text='Update failed: '+$_.Exception.Message}
        finally{Remove-Job $script:updateJob -Force -ErrorAction SilentlyContinue;$script:updateJob=$null;Set-Busy $false;$ui.CancelUpdate.IsEnabled=$false}
    })
    $ui.InstallUpdate.Add_Click({
        if($script:job -or $script:updateJob -or -not $script:updateSource){return}
        if(-not(Confirm 'Install the downloaded update and restart PC Insight? Saved results and recovery records are preserved. The current scan will need to be run again.')){return}
        try {
            $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $installer=Join-Path $PSScriptRoot 'Install.ps1'
            $null=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -SourcePath "{1}" -WaitForPreviousInstance -LaunchAfterInstall' -f $installer,$script:updateSource) -ErrorAction Stop
            $window.Close()
        }catch{Show-Error $_.Exception.Message}
    })
    $updateTimer.Start()
    . "$PSScriptRoot\GuidedOptimizeUI.ps1"
    . "$PSScriptRoot\GameOverlayUI.ps1"
    . "$PSScriptRoot\GpuOverclockUI.ps1"
    . "$PSScriptRoot\GuidedClocksUI.ps1"
    . "$PSScriptRoot\GpuEnduranceUI.ps1"
    $window.Add_Closing({
        param($sender,$eventArgs)
        if($script:clockGuide -and $script:clockGuide.Phase -eq 'Decision'){
            if(-not(Confirm 'Restore the trial clock offsets before closing? Choose No to return and select Keep or Restore.')){$eventArgs.Cancel=$true;return}
            try{Restore-PCClockGuide $script:clockGuide $script:clockJournalPath $script:clockGuidePath}catch{$eventArgs.Cancel=$true;Show-Error $_.Exception.Message;return}
        }
        if($script:guide -and $script:guide.Phase -eq 'Decision'){
            if(-not(Confirm 'A guided GPU change is awaiting your decision. Restore the original limit before closing? Choose No to return and select Keep or Restore.')){$eventArgs.Cancel=$true;return}
            try{Restore-PCGuide $script:guide $script:gpuJournalPath $script:guidePath}
            catch{$eventArgs.Cancel=$true;Show-Error $_.Exception.Message;return}
        }
        $updateTimer.Stop(); if($script:updateJob){Stop-UpdateTask}; $timer.Stop(); Cancel-Task -Force
        if($script:clockGuide -and $script:clockGuide.Phase -eq 'RecoveryRequired'){[Windows.MessageBox]::Show('Clock restoration could not be verified. Saved originals remain available on Tuning after relaunch.','PC Insight recovery')|Out-Null}
        if($script:guide -and $script:guide.Phase -eq 'RecoveryRequired'){[Windows.MessageBox]::Show('GPU restoration could not be verified. The recovery record is retained. Open Guided optimization or Tuning to restore it on the next launch.','PC Insight recovery')|Out-Null}
    })
    $null = $window.ShowDialog()
} catch {
    [Windows.MessageBox]::Show($_.Exception.ToString(), 'PC Insight startup error') | Out-Null
    exit 1
} finally {
    if(Get-Command Close-PCGameOverlay -ErrorAction SilentlyContinue){try{Close-PCGameOverlay}catch{}}
    if ($script:job) { Stop-Job $script:job -ErrorAction SilentlyContinue; Remove-Job $script:job -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $script:stopPath -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
