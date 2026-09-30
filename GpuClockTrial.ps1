# A reviewed, temporary clock change. Always restores after the retest; never keeps
# offsets automatically. Hardware calls are injected through GpuOverclock.ps1.
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
        PeakGpuC=$peak;TemperatureSamples=$temps.Count
    }
}
function Assert-PCClockTrialMeasurement($Measurement,$Device) {
    if(-not $Measurement -or $Measurement.Completed -ne $true -or $Measurement.StopReason){throw ('GPU test did not complete. '+$Measurement.StopReason)}
    $rate=[double]$Measurement.DrawsPerSecond;$seconds=[double]$Measurement.Seconds
    if($Measurement.Test -ne 'OpenGL-1280x720-256shader-b8-w5-30s-v2' -or
        $Measurement.GPUName -ne $Device.Name -or [string]::IsNullOrWhiteSpace($Measurement.Renderer) -or
        [string]::IsNullOrWhiteSpace($Measurement.Runtime) -or $Measurement.WarmupSeconds -ne 5 -or
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
function Invoke-PCGpuClockTrial($Selected,$CoreMHz,$MemoryMHz,[string]$JournalPath,[string]$ReportPath,[string]$StopPath,[int]$OwnerId=0,[long]$OwnerStart=0) {
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
    $report=[pscustomobject]@{
        Schema=1;Kind='PCInsight.GpuClockTrial';Id=[guid]::NewGuid().ToString('N');Started=[datetimeoffset]::Now.ToString('o');Finished=$null
        State='Running';Stage='Baseline';Device=($Selected|Select-Object UUID,Name,Driver,CoreMHz,MemoryMHz)
        Requested=[pscustomobject]@{CoreMHz=$core;MemoryMHz=$memory}
        Before=$null;After=$null;ChangePercent=$null;Restoration='Not needed';Message='Measuring original offsets.'
        Limitations='One before/after pair measures this shader workload, not game FPS or long-term stability. Thermal state and background activity affect the change. No artifact or VRAM integrity detection. GPU/driver hangs, app termination or power loss can prevent automatic restoration; the recovery record remains for next launch.'
    }
    Save-PCClockJournal $report $ReportPath
    $ownsRecovery=$false
    try{
        [pscustomobject]@{Kind='TrialStage';Value='Baseline at original offsets'}
        $before=$null
        Invoke-PCClockTrialMeasurement $Selected $StopPath $OwnerId $OwnerStart | ForEach-Object {
            if($_.Kind -eq 'Result'){$before=ConvertTo-PCClockTrialMeasurement $_.Value}
            elseif($_.Kind -in @('Progress','Phase')){$_}
        }
        $report.Before=$before
        Assert-PCClockTrialMeasurement $before $Selected
        Assert-PCClockTrialState $Selected
        $report.Stage='Cooldown';Save-PCClockJournal $report $ReportPath
        [pscustomobject]@{Kind='TrialStage';Value='Cooling down for 10 seconds'}
        Wait-PCClockTrialCooldown $Selected $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        # Recheck immediately before taking ownership of this trial's recovery.
        if(Test-Path -LiteralPath $JournalPath){throw 'A clock recovery record appeared during the baseline. No trial offsets were applied.'}
        $report.Stage='Applying';Save-PCClockJournal $report $ReportPath
        $ownsRecovery=$true
        [pscustomobject]@{Kind='TrialStage';Value='Applying and verifying reviewed offsets'}
        $null=Set-PCGpuClockOffsets $Selected $core $memory $JournalPath
        $afterState=$Selected|Select-Object *;$afterState.CoreMHz=$core;$afterState.MemoryMHz=$memory
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        $report.Stage='Retest';Save-PCClockJournal $report $ReportPath
        [pscustomobject]@{Kind='TrialStage';Value='Retest at reviewed offsets'}
        $after=$null
        Invoke-PCClockTrialMeasurement $afterState $StopPath $OwnerId $OwnerStart | ForEach-Object {
            if($_.Kind -eq 'Result'){$after=ConvertTo-PCClockTrialMeasurement $_.Value}
            elseif($_.Kind -in @('Progress','Phase')){$_}
        }
        $report.After=$after
        Assert-PCClockTrialMeasurement $after $Selected
        Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
        Assert-PCClockTrialState $afterState
        if($before.Test -ne $after.Test -or $before.Renderer -ne $after.Renderer -or $before.Runtime -ne $after.Runtime -or
            [math]::Abs($before.Seconds-$after.Seconds) -gt [math]::Max(2,0.1*$before.Seconds)){
            throw 'Baseline and retest are not comparable; no performance change is reported.'
        }
        $report.ChangePercent=[math]::Round(100*($after.DrawsPerSecond/$before.DrawsPerSecond-1),2)
        $report.State='Completed';$report.Message='Both measurements completed. This is not stability certification.'
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
        try{Save-PCClockJournal $report $ReportPath}catch{$report.Message+=' Trial report could not be saved: '+$_.Exception.Message}
    }
    [pscustomobject]@{Kind='TrialResult';Value=$report}
}
function Format-PCClockTrialReport($Report) {
    if(-not $Report){return 'Run a measured trial to compare original and requested offsets. Original offsets are restored when it finishes.'}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add("$($Report.State) | $($Report.Device.Name)")
    $lines.Add("Core: $($Report.Device.CoreMHz) -> $($Report.Requested.CoreMHz) MHz | Memory: $($Report.Device.MemoryMHz) -> $($Report.Requested.MemoryMHz) MHz")
    foreach($entry in @(@('Baseline',$Report.Before),@('Retest',$Report.After))){
        if($entry[1]){
            $m=$entry[1];$score=if($m.Completed -eq $true -and -not $m.StopReason){[string]$m.DrawsPerSecond}else{'unavailable'}
            $temp=if($null -ne $m.PeakGpuC){"$($m.PeakGpuC) C"}else{'unavailable'}
            $lines.Add("$($entry[0]): $score draws/s | peak GPU: $temp")
        }
    }
    if($null -ne $Report.ChangePercent){$lines.Add(('Measured change: {0:+0.00;-0.00;0.00}% (one pair)' -f $Report.ChangePercent))}
    $lines.Add('Restoration: '+$Report.Restoration);$lines.Add($Report.Message);$lines.Add($Report.Limitations)
    $lines -join "`n"
}
