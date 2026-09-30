# One reviewed +15 MHz core trial; memory stays unchanged. Not an automatic OC scanner.
function New-PCClockGuide($Clock,$Power,[string]$Plan,[string]$Journal) {
    if(Test-Path -LiteralPath $Journal){throw 'Restore saved clock offsets before starting a fresh trial.'}
    Assert-PCClockDevice $Clock $Clock.UUID
    if(-not $Power.Available -or $Power.UUID -ne $Clock.UUID -or $Power.Name -ne $Clock.Name -or $Power.Driver -ne $Clock.Driver){throw 'Clock and power readings must identify the same GPU and driver.'}
    $target=[long]$Clock.CoreMHz+15
    Assert-PCClockTargets $Clock $target $Clock.MemoryMHz
    [pscustomobject]@{Schema=1;Kind='PCInsight.CoreTrial';ID=[guid]::NewGuid().ToString();Phase='RunningBaseline';Clock=$Clock;Device=$Power;Plan=$Plan;TargetCore=[int]$target;Before=@();After=@();Summary='Recording baseline; no clocks changed.';Created=([datetimeoffset]::Now.ToString('o'))}
}
function Save-PCClockGuide($Guide,[string]$Path){Save-JsonAtomic $Guide $Path}
function Read-PCClockGuide([string]$Path){
    $g=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    $id=[guid]::Empty
    if($g.Schema -ne 1 -or $g.Kind -ne 'PCInsight.CoreTrial' -or -not [guid]::TryParse([string]$g.ID,[ref]$id) -or $g.Phase -notin @('RunningBaseline','Review','Applying','RunningAfter','Decision','Kept','Restored','Interrupted','RecoveryRequired')){throw 'Invalid saved core trial. Inspect saved clock recovery on Tuning.'}
    Assert-PCClockDevice $g.Clock $g.Clock.UUID
    if($g.Device.UUID -ne $g.Clock.UUID -or $null -eq (Convert-PCWatts $g.Device.Current) -or [long](ConvertTo-PCClockInteger $g.TargetCore) -ne ([long]$g.Clock.CoreMHz+15)){throw 'Saved core trial metadata is invalid.'}
    $g
}
function Assert-PCClockGuideLive($Guide,[int]$Core){
    $null=Assert-PCGuideLiveState $Guide $Guide.Device.Current
    $clock=Get-PCClockDevice $Guide.Clock.UUID;Assert-PCClockDevice $clock $Guide.Clock.UUID
    if($clock.Driver -ne $Guide.Clock.Driver -or $clock.CoreMHz -ne $Core -or $clock.MemoryMHz -ne $Guide.Clock.MemoryMHz){throw 'Reported clock offsets or driver changed outside the core trial.'}
    $clock
}
function Assert-PCClockGuideBatch($Guide,$Records,[int]$Core){
    Assert-PCGuideBatch $Guide $Records $Guide.Device.Current
    $duration=if(@($Guide.Before).Count){$Guide.Before[0].Seconds}else{@($Records)[0].Seconds}
    foreach($r in @($Records)){
        if([math]::Abs($r.Seconds-$duration) -gt [math]::Max(2,0.1*$duration)){throw 'Benchmark durations differ too much for this trial.'}
        $clocks=@($r.PowerStateAtStart.ClockOffsets|Where-Object UUID -eq $Guide.Clock.UUID)
        if($r.PowerStateAtStart.ClockIssue -or $clocks.Count -ne 1 -or -not $clocks[0].Available -or $clocks[0].Driver -ne $Guide.Clock.Driver -or $clocks[0].CoreMHz -ne $Core -or $clocks[0].MemoryMHz -ne $Guide.Clock.MemoryMHz){throw 'Benchmark clock metadata does not match this trial.'}
        if(-not $r.Renderer -or -not $r.DriverVersion -or -not $r.CPUName -or -not $r.Runtime -or $r.Workers -le 0 -or $r.Seconds -lt 25 -or $r.Seconds -gt 40){throw 'GPU benchmark configuration or duration is incomplete.'}
    }
}
function Assert-PCClockGuideJournal($Guide,[string]$Journal){
    $j=Read-PCClockJournal $Journal
    if($j.UUID -ne $Guide.Clock.UUID -or $j.OriginalCore -ne $Guide.Clock.CoreMHz -or $j.OriginalMemory -ne $Guide.Clock.MemoryMHz){throw 'Saved clock recovery belongs to a different trial. Use manual restoration on Tuning.'}
    $j
}
function Restore-PCClockGuide($Guide,[string]$Journal,[string]$Path){
    if(Test-Path -LiteralPath $Journal){$null=Assert-PCClockGuideJournal $Guide $Journal;$null=Restore-PCGpuClockOffsets $Journal}
    else{
        # Missing journal is not evidence of a successful restore: require live readback.
        $c=Get-PCClockDevice $Guide.Clock.UUID;Assert-PCClockDevice $c $Guide.Clock.UUID
        if($c.CoreMHz -ne $Guide.Clock.CoreMHz -or $c.MemoryMHz -ne $Guide.Clock.MemoryMHz){throw 'Original offsets cannot be verified and the recovery record is missing.'}
    }
    $Guide.Phase='Restored';$Guide.Summary='Original core and memory offsets restored and read back. No stability claim.';Save-PCClockGuide $Guide $Path
}
function Stop-PCClockGuide($Guide,[string]$Journal,[string]$Path,[string]$Reason){
    if(-not $Guide){return}
    if($Guide.Phase -in @('Applying','RunningAfter','Decision','RecoveryRequired')){
        try{Restore-PCClockGuide $Guide $Journal $Path;$Guide.Summary=$Reason+' Original offsets restored and read back.'}
        catch{$Guide.Phase='RecoveryRequired';$Guide.Summary=$Reason+' Restore could not be verified: '+$_.Exception.Message}
    }else{$Guide.Phase='Interrupted';$Guide.Summary=$Reason+' No trial clock write was made.'}
    Save-PCClockGuide $Guide $Path
}
function Apply-PCClockGuide($Guide,[string]$Journal,[string]$Path){
    if($Guide.Phase -ne 'Review'){throw 'Complete a fresh baseline first.'}
    Assert-PCClockGuideBatch $Guide $Guide.Before $Guide.Clock.CoreMHz
    if(Test-Path -LiteralPath $Journal){throw 'An existing clock recovery record blocks this trial.'}
    $clock=Assert-PCClockGuideLive $Guide $Guide.Clock.CoreMHz
    $Guide.Phase='Applying';Save-PCClockGuide $Guide $Path
    try{
        $null=Set-PCGpuClockOffsets $clock $Guide.TargetCore $Guide.Clock.MemoryMHz $Journal
        $Guide.Phase='RunningAfter';$Guide.Summary='Offsets read back; recording three retest runs.';Save-PCClockGuide $Guide $Path
    }catch{Stop-PCClockGuide $Guide $Journal $Path $_.Exception.Message;throw}
}
function Complete-PCClockGuide($Guide,$Records,[string]$Journal,[string]$Path){
    if($Guide.Phase -notin @('RunningBaseline','RunningAfter')){throw 'No guided clock batch is running.'}
    $baseline=$Guide.Phase -eq 'RunningBaseline';$core=if($baseline){$Guide.Clock.CoreMHz}else{$Guide.TargetCore}
    try{
        Assert-PCClockGuideBatch $Guide $Records $core;$null=Assert-PCClockGuideLive $Guide $core
        if($baseline){
            if((Get-PCGroupStats $Records).SpreadPercent -gt 5){throw 'Baseline variability exceeds 5%. Start a new baseline after closing background workloads.'}
            $Guide.Before=@($Records);$Guide.Phase='Review';$Guide.Summary="Baseline complete. Review a +15 MHz core trial ($($Guide.TargetCore) MHz offset). Memory remains $($Guide.Clock.MemoryMHz) MHz."
        }else{
            $Guide.After=@($Records);$a=Get-PCGroupStats $Guide.Before;$b=Get-PCGroupStats $Guide.After
            $overlap=$a.Min -le $b.Max -and $b.Min -le $a.Max
            $verdict=if($a.SpreadPercent -gt 5 -or $b.SpreadPercent -gt 5){'Inconclusive: high variability.'}elseif($overlap){'Inconclusive: score ranges overlap.'}elseif($b.Median -gt $a.Median){'Higher measured throughput; repeat to confirm.'}else{'Lower measured throughput; restore recommended.'}
            $Guide.Phase='Decision';$Guide.Summary=('{0} Median {1:N1} -> {2:N1} draws/s ({3:+0.0;-0.0;0.0}%). Three runs per side. This is not game FPS or stability certification. Choose Keep or Restore.' -f $verdict,$a.Median,$b.Median,(100*($b.Median/$a.Median-1)))
        }
        if(-not $baseline){
            $old=@(Get-PCBatchSensorPeaks $Guide.Before $Guide.Before 'GPU Core' 'Temperature')
            $new=@(Get-PCBatchSensorPeaks $Guide.After $Guide.After 'GPU Core' 'Temperature')
            if($old.Count -eq 3 -and $new.Count -eq 3){$Guide.Summary+=(' Median sampled GPU temperature peaks: {0:N1} -> {1:N1} C.' -f (Get-PCMedian $old),(Get-PCMedian $new))}else{$Guide.Summary+=' GPU temperature comparison unavailable: all six matching sensor records are required.'}
        }
        Save-PCClockGuide $Guide $Path
    }catch{Stop-PCClockGuide $Guide $Journal $Path $_.Exception.Message;throw}
}
function Keep-PCClockGuide($Guide,[string]$Journal,[string]$Path){
    if($Guide.Phase -ne 'Decision'){throw 'Complete the retest before choosing Keep.'}
    $null=Assert-PCClockGuideLive $Guide $Guide.TargetCore;$j=Assert-PCClockGuideJournal $Guide $Journal
    if($j.State -ne 'Applied' -or $j.LastCore -ne $Guide.TargetCore -or $j.LastMemory -ne $Guide.Clock.MemoryMHz){throw 'Recovery record does not match the verified trial offsets.'}
    $Guide.Phase='Kept';$Guide.Summary='You kept the read-back offsets. Original values remain saved; restore is available. No automatic startup application.';Save-PCClockGuide $Guide $Path
}
