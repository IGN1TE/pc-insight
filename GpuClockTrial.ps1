# A reviewed, temporary clock change. Always restores after the retest; never keeps
# offsets automatically. Hardware calls are injected through GpuOverclock.ps1.
. (Join-Path $PSScriptRoot 'GpuClockTrialHistory.ps1')
. (Join-Path $PSScriptRoot 'GpuClockTrialTelemetry.ps1')
function Assert-PCClockTrialRunning([string]$StopPath,[int]$OwnerId=0,[long]$OwnerStart=0) {
    if($StopPath -and (Test-Path -LiteralPath $StopPath)){throw 'GPU clock trial cancelled.'}
    if($OwnerId -gt 0){
        try{$owner=Get-Process -Id $OwnerId -ErrorAction Stop;if($owner.StartTime.Ticks -ne $OwnerStart){throw 'Owner changed'}}
        catch{throw 'PC Insight closed; stopping the GPU clock trial.'}
    }
}
function Assert-PCClockTrialState($Expected) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $live=Get-PCClockDevice $Expected.UUID
    if($watch.Elapsed.TotalSeconds -gt 3){throw 'GPU clock query exceeded 3 seconds.'}
    Assert-PCClockDevice $live $Expected.UUID
    Assert-PCClockApplyTemperature $live
    if($live.Driver -ne $Expected.Driver -or $live.CoreMHz -ne $Expected.CoreMHz -or $live.MemoryMHz -ne $Expected.MemoryMHz){
        throw 'GPU offsets or driver changed during the trial. The comparison has been stopped.'
    }
}
function ConvertTo-PCClockTrialMeasurement($Result) {
    $peak=$null
    $temps=@($Result.Frames | ForEach-Object {$_.Sensors} | Where-Object {
        $_.Parent -match '^/gpu' -and $_.Type -eq 'Temperature' -and $_.Name -eq 'GPU Core' -and $_.HardwareName -eq $Result.GPUName -and $null -ne $_.Value
    } | ForEach-Object {[double]$_.Value})
    if($temps.Count){$peak=($temps|Measure-Object -Maximum).Maximum}
    [pscustomobject]@{
        Test=$Result.Test;Timestamp=$Result.Timestamp;Seconds=$Result.Seconds;Runtime=$Result.Runtime
        Renderer=$Result.Renderer;GPUName=$Result.GPUName;WarmupSeconds=$Result.WarmupSeconds
        Completed=$Result.Completed;StopReason=$Result.StopReason;DrawsPerSecond=$Result.GpuFramesPerSecond
        PeakGpuC=$peak;TemperatureSamples=$temps.Count;Telemetry=(ConvertTo-PCClockTrialTelemetry $Result)
    }
}
function Assert-PCClockTrialMeasurement($Measurement,$Device) {
    if(-not $Measurement -or $Measurement.Completed -ne $true -or $Measurement.StopReason){throw ('GPU test did not complete. '+$Measurement.StopReason)}
    $rate=[double]$Measurement.DrawsPerSecond;$seconds=[double]$Measurement.Seconds
    if($Measurement.Test -ne 'OpenGL-1280x720-256shader-b8-w5-30s-v2' -or
        $Measurement.GPUName -ne $Device.Name -or [string]::IsNullOrWhiteSpace($Measurement.Renderer) -or
        [string]::IsNullOrWhiteSpace($Measurement.Runtime) -or $Measurement.WarmupSeconds -ne 5 -or
        $Measurement.TemperatureSamples -lt 1 -or $null -eq $Measurement.PeakGpuC -or
        [double]::IsNaN([double]$Measurement.PeakGpuC) -or [double]::IsInfinity([double]$Measurement.PeakGpuC) -or
        $Measurement.PeakGpuC -le 0 -or $Measurement.PeakGpuC -ge 85 -or
        [double]::IsNaN($rate) -or [double]::IsInfinity($rate) -or $rate -le 0 -or
        [double]::IsNaN($seconds) -or [double]::IsInfinity($seconds) -or $seconds -lt 29.5 -or $seconds -gt 45){
        throw 'GPU test identity, duration or score is invalid for this trial.'
    }
}
function Invoke-PCClockTrialMeasurement($Expected,[string]$StopPath,[int]$OwnerId,[long]$OwnerStart) {
    $guard={
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialState $Expected
    }.GetNewClosure()
    Invoke-PCExtendedTest -Kind gpu -StopPath $StopPath -ExpectedGpuName $Expected.Name -Guard $guard
}
function Wait-PCClockTrialCooldown($Expected,[string]$StopPath,[int]$OwnerId,[long]$OwnerStart) {
    # Match the existing repeated GPU test cooldown. Poll throughout the wait.
    for($i=0;$i -lt 10;$i++){
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialState $Expected
        Start-Sleep -Milliseconds 1000
    }
}
function Get-PCClockTrialEnvironment($Device) {
    # Query at run boundaries, outside the scored workload. Polling nvidia-smi
    # while scoring would add management-process overhead to the measurement.
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $plan=Get-ActivePlan
    $power=Get-PCDeviceById $Device.UUID
    if($watch.Elapsed.TotalSeconds -gt 3){throw 'Trial power-setting query exceeded 3 seconds.'}
    if($plan -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$' -or
        $power.UUID -ne $Device.UUID -or $power.Driver -ne $Device.Driver -or
        $null -eq (Convert-PCWatts $power.Current)){
        throw 'A matching GPU power limit, driver and Windows power plan are required for the trial.'
    }
    [pscustomobject]@{Plan=$plan;UUID=$power.UUID;Driver=$power.Driver;PowerLimitWatts=[double]$power.Current}
}
function Assert-PCClockTrialEnvironment($Expected,$Actual) {
    if($Actual.Plan -ne $Expected.Plan -or $Actual.UUID -ne $Expected.UUID -or
        $Actual.Driver -ne $Expected.Driver -or [math]::Abs($Actual.PowerLimitWatts-$Expected.PowerLimitWatts) -gt 0.5){
        throw 'GPU power limit or Windows power plan changed. Trial stopped; no clock performance comparison is available.'
    }
}
function Assert-PCClockTrialComparable($Reference,$Measurement) {
    if($Reference.Test -ne $Measurement.Test -or $Reference.Renderer -ne $Measurement.Renderer -or
        $Reference.Runtime -ne $Measurement.Runtime -or $Reference.GPUName -ne $Measurement.GPUName -or
        $Reference.WarmupSeconds -ne $Measurement.WarmupSeconds -or
        [math]::Abs($Reference.Seconds-$Measurement.Seconds) -gt [math]::Max(2,0.1*$Reference.Seconds)){
        throw 'Baseline and retest runs are not comparable; no performance change is reported.'
    }
}
function Get-PCClockTrialSummary($Runs) {
    $valid=@($Runs|Where-Object {$_.Eligible -eq $true})
    if(-not $valid.Count){return $null}
    $rates=@($valid|ForEach-Object {[double]$_.DrawsPerSecond}|Sort-Object)
    $median=Get-PCMedian $rates
    [pscustomobject]@{
        Count=$rates.Count;Median=$median;Min=$rates[0];Max=$rates[-1]
        SpreadPercent=100*($rates[-1]-$rates[0])/$median
        MedianStartGpuC=(Get-PCMedian @($valid|ForEach-Object {$_.StartGpuC}))
        MedianPeakGpuC=(Get-PCMedian @($valid|ForEach-Object {$_.PeakGpuC}))
    }
}
function Invoke-PCClockTrialBatch($Expected,$Environment,$Report,[ValidateSet('Before','After')][string]$Side,[string]$ReportPath,[string]$StopPath,[int]$OwnerId,[long]$OwnerStart) {
    $label=if($Side -eq 'Before'){'Baseline'}else{'Retest'}
    for($run=1;$run -le $Report.RunCount;$run++){
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialState $Expected
        $startEnvironment=Get-PCClockTrialEnvironment $Expected
        Assert-PCClockTrialEnvironment $Environment $startEnvironment
        $startDevice=Get-PCClockDevice $Expected.UUID;Assert-PCClockApplyTemperature $startDevice
        $Report.Stage=$label;$Report.RunIndex=$run;Save-PCClockJournal $Report $ReportPath
        [pscustomobject]@{Kind='TrialStage';Value="$label $run of $($Report.RunCount)"}
        $measurement=$null
        Invoke-PCClockTrialMeasurement $Expected $StopPath $OwnerId $OwnerStart | ForEach-Object {
            if($_.Kind -eq 'Result'){$measurement=ConvertTo-PCClockTrialMeasurement $_.Value}
            elseif($_.Kind -in @('Progress','Phase')){$_}
        }
        if(-not $measurement){throw 'GPU test ended without a measurement.'}
        $measurement|Add-Member NoteProperty RunIndex $run
        $measurement|Add-Member NoteProperty StartGpuC ([double]$startDevice.TemperatureC)
        $measurement|Add-Member NoteProperty EnvironmentBefore $startEnvironment
        $measurement|Add-Member NoteProperty EnvironmentAfter $null
        $measurement|Add-Member NoteProperty Eligible $false
        $measurement|Add-Member NoteProperty Exclusion $null
        $Report.($Side+'Runs')=@($Report.($Side+'Runs'))+@($measurement)
        try{
            Assert-PCClockTrialMeasurement $measurement $Expected
            Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
            Assert-PCClockTrialState $Expected
            $measurement.EnvironmentAfter=Get-PCClockTrialEnvironment $Expected
            Assert-PCClockTrialEnvironment $Environment $measurement.EnvironmentAfter
            Assert-PCClockTrialComparable $Report.BeforeRuns[0] $measurement
            $measurement.Eligible=$true
            $Report.($Side+'Summary')=Get-PCClockTrialSummary $Report.($Side+'Runs')
        }catch{$measurement.Exclusion=$_.Exception.Message;throw}
        finally{Save-PCClockJournal $Report $ReportPath}
        if($run -lt $Report.RunCount){
            [pscustomobject]@{Kind='TrialStage';Value="$label $run complete; cooling down for 10 seconds"}
            Wait-PCClockTrialCooldown $Expected $StopPath $OwnerId $OwnerStart
        }
    }
}
function Complete-PCClockTrialComparison($Report) {
    $before=$Report.BeforeSummary;$after=$Report.AfterSummary
    if(-not $before -or -not $after -or $before.Count -ne $Report.RunCount -or $after.Count -ne $Report.RunCount){throw 'Incomplete run groups cannot be compared.'}
    $Report.ChangePercent=[math]::Round(100*($after.Median/$before.Median-1),2)
    $reasons=[Collections.Generic.List[string]]::new()
    if($Report.RunCount -eq 1){$reasons.Add('Quick trial: one pair cannot assess repeatability.')}
    if($Report.ChangePercent -eq 0){$reasons.Add('Median difference rounds to 0.00%.')}
    if($before.SpreadPercent -gt 5 -or $after.SpreadPercent -gt 5){$reasons.Add('Run spread exceeds the 5% variability heuristic.')}
    if($after.Min -le $before.Max -and $before.Min -le $after.Max){$reasons.Add('Observed run ranges overlap.')}
    if([math]::Abs($after.MedianStartGpuC-$before.MedianStartGpuC) -gt 5){$reasons.Add('Median starting temperatures differ by more than the 5 C comparison heuristic.')}
    $Report.ComparisonReasons=@($reasons.ToArray())
    $Report.Comparison=if($reasons.Count){'Inconclusive'}elseif($Report.ChangePercent -gt 0){'Observed higher throughput'}else{'Observed lower throughput'}
}
function Invoke-PCGpuClockTrial($Selected,$CoreMHz,$MemoryMHz,[string]$JournalPath,[string]$ReportPath,[string]$StopPath,[int]$OwnerId=0,[long]$OwnerStart=0,[ValidateSet(1,3)][int]$RunCount=3) {
    # Preflight failures are intentionally outside recovery: an existing journal
    # belongs to an earlier action and must never be adopted by this trial.
    if(-not (Test-PCClockAdministrator)){throw 'Reopen PC Insight as administrator to run a GPU clock trial.'}
    if(Test-Path -LiteralPath $JournalPath){throw 'Restore saved clock offsets before starting a new trial.'}
    if([IO.Path]::GetFullPath($ReportPath) -eq [IO.Path]::GetFullPath($JournalPath)){throw 'Trial report and recovery paths must be different.'}
    $core=ConvertTo-PCClockInteger $CoreMHz;$memory=ConvertTo-PCClockInteger $MemoryMHz
    Assert-PCClockDevice $Selected $Selected.UUID
    Assert-PCClockTargets $Selected $core $memory
    Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
    $devices=@(Get-PCClockDevices)
    if($devices.Count -ne 1 -or $devices[0].UUID -ne $Selected.UUID){throw 'Measured clock trials currently require exactly one NVIDIA GPU, to avoid testing a different adapter.'}
    Assert-PCClockTrialState $Selected
    if($core -eq $Selected.CoreMHz -and $memory -eq $Selected.MemoryMHz){throw 'Enter a different core or memory offset to measure a change.'}
    $environment=Get-PCClockTrialEnvironment $Selected
    # Preserve the previous experiment before replacing the last-run checkpoint.
    # Failure here aborts before any hardware write.
    Protect-PCPreviousClockTrial $ReportPath
    $report=[pscustomobject]@{
        Schema=2;Kind='PCInsight.GpuClockTrial';Id=[guid]::NewGuid().ToString('N');Started=[datetimeoffset]::Now.ToString('o');Finished=$null
        State='Running';Stage='Baseline';Device=($Selected|Select-Object UUID,Name,Driver,CoreMHz,MemoryMHz)
        Requested=[pscustomobject]@{CoreMHz=$core;MemoryMHz=$memory}
        RunCount=$RunCount;RunIndex=0;Environment=$environment;BeforeRuns=@();AfterRuns=@();BeforeSummary=$null;AfterSummary=$null
        Comparison='Unavailable';ComparisonReasons=@();ChangePercent=$null;Restoration='Not needed';Message='Measuring original offsets.'
        Limitations='Shader throughput is not game FPS or long-term stability. Three runs do not establish statistical significance or causation. The 5% spread and 5 C starting-temperature cutoffs are comparison heuristics. Fixed cooldown does not equalize temperature. Power settings are checked at run boundaries; transient changes between queries may be missed. No artifact or VRAM integrity detection. GPU/driver hangs, app termination or power loss can prevent automatic restoration; the recovery record remains for next launch.'
    }
    Save-PCClockJournal $report $ReportPath
    $ownsRecovery=$false
    try{
        Invoke-PCClockTrialBatch $Selected $environment $report 'Before' $ReportPath $StopPath $OwnerId $OwnerStart
        if($RunCount -gt 1 -and $report.BeforeSummary.SpreadPercent -gt 5){throw 'Baseline spread exceeds 5%. No trial offsets were applied. Close background workloads and repeat under consistent conditions.'}
        Assert-PCClockTrialState $Selected
        $report.Stage='Cooldown';Save-PCClockJournal $report $ReportPath
        [pscustomobject]@{Kind='TrialStage';Value='Cooling down for 10 seconds'}
        Wait-PCClockTrialCooldown $Selected $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialEnvironment $environment (Get-PCClockTrialEnvironment $Selected)
        # Recheck immediately before taking ownership of this trial's recovery.
        if(Test-Path -LiteralPath $JournalPath){throw 'A clock recovery record appeared during the baseline. No trial offsets were applied.'}
        $report.Stage='Applying';Save-PCClockJournal $report $ReportPath
        $ownsRecovery=$true
        [pscustomobject]@{Kind='TrialStage';Value='Applying and verifying reviewed offsets'}
        $null=Set-PCGpuClockOffsets $Selected $core $memory $JournalPath
        $afterState=$Selected|Select-Object *;$afterState.CoreMHz=$core;$afterState.MemoryMHz=$memory
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        $report.Stage='Retest';Save-PCClockJournal $report $ReportPath
        Invoke-PCClockTrialBatch $afterState $environment $report 'After' $ReportPath $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialState $afterState
        Complete-PCClockTrialComparison $report
        $report.State='Completed';$report.Message='All measurements completed. This is not stability certification.'
    }catch{
        $report.State='Stopped';$report.ChangePercent=$null;$report.Message=$_.Exception.Message
    }finally{
        if($ownsRecovery){
            $report.Stage='Restoring'
            # Recovery must run even if report persistence, cancellation or telemetry failed.
            try{
                if(Test-Path -LiteralPath $JournalPath){
                    $j=Read-PCClockJournal $JournalPath
                    if($j.UUID -ne $Selected.UUID -or $j.OriginalCore -ne $Selected.CoreMHz -or $j.OriginalMemory -ne $Selected.MemoryMHz){throw 'Clock recovery record no longer matches this trial.'}
                    $null=Restore-PCGpuClockOffsets $JournalPath
                }else{
                    # A failed pre-write check/journal save can leave nothing to
                    # restore. Confirm the originals read-only; never guess a write.
                    $live=Get-PCClockDevice $Selected.UUID;Assert-PCClockDevice $live $Selected.UUID
                    if($live.CoreMHz -ne $Selected.CoreMHz -or $live.MemoryMHz -ne $Selected.MemoryMHz){throw 'Clock recovery record is missing and original offsets are not present.'}
                }
                $report.Restoration='Verified';$report.Message+=' Original offsets restored and read back.'
            }catch{
                $report.Restoration='RecoveryRequired';$report.State='RecoveryRequired';$report.ChangePercent=$null
                $report.Message+=' Restoration could not be verified: '+$_.Exception.Message
            }
        }
        $report.Stage='Finished';$report.Finished=[datetimeoffset]::Now.ToString('o')
        if($report.State -ne 'Completed'){$report.Comparison='Unavailable';$report.ComparisonReasons=@($report.Message)}
        try{Save-PCClockJournal $report $ReportPath}catch{$report.Message+=' Trial report could not be saved: '+$_.Exception.Message}
        try{Save-PCClockTrialHistory $report (Get-PCClockTrialHistoryFolder $ReportPath)}catch{$report.Message+=' Trial history could not be saved: '+$_.Exception.Message}
    }
    [pscustomobject]@{Kind='TrialResult';Value=$report}
}
function Read-PCClockTrialReport([string]$Path) {
    $saved=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($saved.Schema -notin @(1,2) -or $saved.Kind -ne 'PCInsight.GpuClockTrial'){throw 'Unknown trial report format.'}
    if($saved.Schema -eq 2 -and $saved.RunCount -notin @(1,3)){throw 'Invalid trial run count in saved report.'}
    if($saved.State -eq 'Running'){
        $saved.State='Interrupted';$saved.ChangePercent=$null;$saved.Restoration='Unverified'
        $saved.Message='The previous trial did not finish. Inspect saved clock recovery before continuing.'
        if($saved.Schema -eq 2){$saved.Comparison='Unavailable';$saved.ComparisonReasons=@($saved.Message)}
    }
    $saved
}
function Format-PCClockTrialReport($Report) {
    if(-not $Report){return 'Run a measured trial to compare original and requested offsets. Original offsets are restored when it finishes.'}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add("$($Report.State) | $($Report.Device.Name)")
    $lines.Add("Core: $($Report.Device.CoreMHz) -> $($Report.Requested.CoreMHz) MHz | Memory: $($Report.Device.MemoryMHz) -> $($Report.Requested.MemoryMHz) MHz")
    if($Report.Schema -eq 2){
        $lines.Add("$($Report.RunCount) runs per setting | Windows plan: $($Report.Environment.Plan) | GPU power limit: $($Report.Environment.PowerLimitWatts) W")
        foreach($side in 'Before','After'){
            $label=if($side -eq 'Before'){'Baseline'}else{'Retest'}
            $summary=$Report.($side+'Summary')
            if($summary){$lines.Add(('{0}: {1}/{2} valid runs | median {3:N2} draws/s | range {4:N2}-{5:N2} | spread {6:N2}%' -f $label,$summary.Count,$Report.RunCount,$summary.Median,$summary.Min,$summary.Max,$summary.SpreadPercent))}
            foreach($m in @($Report.($side+'Runs'))){
                if($m.Eligible){$lines.Add(("  Run {0}: {1:N2} draws/s | start {2} C | sampled peak {3} C" -f $m.RunIndex,$m.DrawsPerSecond,$m.StartGpuC,$m.PeakGpuC))}
                else{$lines.Add("  Run $($m.RunIndex): excluded. $($m.Exclusion)")}
            }
        }
        if($null -ne $Report.ChangePercent){$lines.Add(('Measured median change: {0:+0.00;-0.00;0.00}%' -f $Report.ChangePercent))}
        $lines.Add('Comparison: '+$Report.Comparison)
        foreach($reason in @($Report.ComparisonReasons)){$lines.Add($reason)}
    }else{foreach($entry in @(@('Baseline',$Report.Before),@('Retest',$Report.After))){
        if($entry[1]){
            $m=$entry[1];$score=if($m.Completed -eq $true -and -not $m.StopReason){[string]$m.DrawsPerSecond}else{'unavailable'}
            $temp=if($null -ne $m.PeakGpuC){"$($m.PeakGpuC) C"}else{'unavailable'}
            $lines.Add("$($entry[0]): $score draws/s | peak GPU: $temp")
        }
    }
    if($null -ne $Report.ChangePercent){$lines.Add(('Measured change: {0:+0.00;-0.00;0.00}% (one pair)' -f $Report.ChangePercent))}
    }
    $lines.Add('Restoration: '+$Report.Restoration);$lines.Add($Report.Message);$lines.Add($Report.Limitations)
    $lines -join "`n"
}
