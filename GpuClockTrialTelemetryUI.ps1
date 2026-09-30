# Saved telemetry only. Selection handlers have no device or workload calls.
$script:clockTelemetryRefreshing=$false
function Show-PCClockTrialTelemetryPlot {
    if($script:clockTelemetryRefreshing){return}
    $ui.ClockTrialTelemetryChart.Children.Clear()
    $ui.ClockTrialTelemetryScale.Text='';$ui.ClockTrialTelemetryTime.Text=''
    $entry=$ui.ClockTrialTelemetryRun.SelectedItem;$channel=$ui.ClockTrialTelemetrySensor.SelectedItem
    $ui.ClockTrialTelemetrySummary.Text='Select a run and a sensor to inspect retained readings.'
    if(-not $entry -or -not $channel){return}
    $view=Get-PCClockTrialTelemetryView $entry.Run $channel
    $ui.ClockTrialTelemetrySummary.Text=$view.Summary
    if($view.Notes){$ui.ClockTrialTelemetrySummary.Text+="`n"+$view.Notes}
    if($entry.Run.Eligible -ne $true){$ui.ClockTrialTelemetrySummary.Text+="`nExcluded run: $($entry.Run.Exclusion)"}
    $plot=$view.Plot;if(-not $plot){return}
    $ui.ClockTrialTelemetryScale.Text=('{0:N1} to {1:N1} {2} (automatic scale)' -f $plot.Minimum,$plot.Maximum,$channel.Unit)
    $ui.ClockTrialTelemetryTime.Text=('{0:N1} seconds from the first retained timestamp, including preparation/warm-up. Hover for readings. Gaps are not filled.' -f $plot.Seconds)
    $line=$null
    foreach($point in $plot.Points){
        if($point.BreakBefore -or -not $line){
            $line=[Windows.Shapes.Polyline]::new();$line.Stroke=[Windows.Media.Brushes]::MediumPurple;$line.StrokeThickness=2
            $null=$ui.ClockTrialTelemetryChart.Children.Add($line)
        }
        $line.Points.Add([Windows.Point]::new($point.X,$point.Y))
        $dot=[Windows.Shapes.Ellipse]::new();$dot.Width=5;$dot.Height=5;$dot.Fill=[Windows.Media.Brushes]::Turquoise
        $dot.ToolTip=('{0} | {1:N2} {2}' -f $point.Timestamp,$point.Value,$channel.Unit)
        [Windows.Controls.Canvas]::SetLeft($dot,$point.X-2.5);[Windows.Controls.Canvas]::SetTop($dot,$point.Y-2.5)
        $null=$ui.ClockTrialTelemetryChart.Children.Add($dot)
    }
}
function Show-PCClockTrialTelemetryRun {
    if($script:clockTelemetryRefreshing){return}
    $key=$ui.ClockTrialTelemetrySensor.SelectedItem.IdentityKey;$entry=$ui.ClockTrialTelemetryRun.SelectedItem
    $script:clockTelemetryRefreshing=$true
    try{
        $channels=@(Get-PCClockTrialTelemetryChannels $entry.Run)
        $ui.ClockTrialTelemetrySensor.ItemsSource=$channels
        $ui.ClockTrialTelemetrySensor.IsEnabled=$channels.Count -gt 0
        $match=@($channels|Where-Object IdentityKey -eq $key)
        if($match.Count){$ui.ClockTrialTelemetrySensor.SelectedItem=$match[0]}elseif($channels.Count){$ui.ClockTrialTelemetrySensor.SelectedIndex=0}
    }finally{$script:clockTelemetryRefreshing=$false}
    Show-PCClockTrialTelemetryPlot
    if(-not $channels.Count){
        $ui.ClockTrialTelemetrySummary.Text='This run has no retained GPU sensor timeline. Older reports remain available as score summaries.'
        if($entry.Run.Telemetry.Notes){$ui.ClockTrialTelemetrySummary.Text+="`n"+($entry.Run.Telemetry.Notes -join ' ')}
    }
}
function Show-PCClockTrialTelemetry {
    $report=$ui.ClockTrialHistory.SelectedItem.Report;$key=$ui.ClockTrialTelemetryRun.SelectedItem.Key
    $script:clockTelemetryRefreshing=$true
    try{
        $runs=@(Get-PCClockTrialTelemetryRuns $report)
        $ui.ClockTrialTelemetryRun.ItemsSource=$runs;$ui.ClockTrialTelemetryRun.IsEnabled=$runs.Count -gt 0
        $match=@($runs|Where-Object Key -eq $key)
        if($match.Count){$ui.ClockTrialTelemetryRun.SelectedItem=$match[0]}elseif($runs.Count){$ui.ClockTrialTelemetryRun.SelectedIndex=0}
    }finally{$script:clockTelemetryRefreshing=$false}
    Show-PCClockTrialTelemetryRun
    if(-not $runs.Count){$ui.ClockTrialTelemetrySummary.Text='No per-run telemetry is available for this saved trial.'}
}
$ui.ClockTrialTelemetryRun.Add_SelectionChanged({Show-PCClockTrialTelemetryRun})
$ui.ClockTrialTelemetrySensor.Add_SelectionChanged({Show-PCClockTrialTelemetryPlot})
Show-PCClockTrialTelemetry
