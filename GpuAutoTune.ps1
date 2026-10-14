# Bounded core scan using the existing NVML transaction and original-offset journal.
# A scan tests at most +15/+30/+45 MHz above its starting offset; it never searches to failure.
function Enable-PCGpuAutoScan($Guide) {
    Assert-PCClockTargets $Guide.Clock ([int]$Guide.Clock.CoreMHz+45) $Guide.Clock.MemoryMHz
    $Guide | Add-Member NoteProperty ScanMode 'Core45' -Force
    $Guide | Add-Member NoteProperty ScanResults @() -Force
    $Guide | Add-Member NoteProperty ScanFinished $false -Force
    $Guide | Add-Member NoteProperty RecommendedCore $null -Force
    $Guide | Add-Member NoteProperty ScanSummary '' -Force
    $Guide.Summary='Recording three baseline runs for a bounded +15 / +30 / +45 MHz core scan. No clocks changed.'
}
function Assert-PCGpuAutoScan($Guide) {
    if($Guide.ScanMode -ne 'Core45'){throw 'Unknown GPU scan mode.'}
    $step=[long](ConvertTo-PCClockInteger $Guide.TargetCore)-[long]$Guide.Clock.CoreMHz
    if($step -notin @(15,30,45) -or @($Guide.ScanResults).Count -gt 3){throw 'GPU scan exceeds its reviewed three-step limit.'}
    Assert-PCClockTargets $Guide.Clock $Guide.TargetCore $Guide.Clock.MemoryMHz
}
function Assert-PCGpuScanBatch($Guide,$Records) {
    $rows=@($Records)
    $baselineCpu=if(@($Guide.Before).Count){Get-PCRecordedCpuPowerSignature $Guide.Before[0].PowerStateAtStart}else{Get-PCRecordedCpuPowerSignature $rows[0].PowerStateAtStart}
    foreach($r in $rows){
        if(-not $r.PowerStateAtEnd -or (Get-PCPowerSignature $r.PowerStateAtStart) -cne (Get-PCPowerSignature $r.PowerStateAtEnd)){throw 'GPU scan requires matching settings at both ends of every run.'}
        if((Get-PCRecordedCpuPowerSignature $r.PowerStateAtStart) -cne $baselineCpu){throw 'CPU power context changed during the GPU scan.'}
    }
    $peaks=@(Get-PCBatchSensorPeaks $rows $rows 'GPU Core' 'Temperature')
    if($peaks.Count -ne 3){throw 'All three runs need matching GPU temperature samples.'}
    if(@($peaks | Where-Object {$_ -le 0 -or $_ -ge 80}).Count){throw 'The scan stopped at its conservative 80 C sampled GPU cutoff. Original offsets will be restored; this cutoff is not a stability guarantee.'}
}
function Get-PCGpuScanRecommendation($Guide) {
    Assert-PCGpuAutoScan $Guide
    Assert-PCClockGuideBatch $Guide $Guide.Before $Guide.Clock.CoreMHz
    Assert-PCGpuScanBatch $Guide $Guide.Before
    $base=Get-PCGroupStats $Guide.Before
    if($base.SpreadPercent -gt 5){throw 'Baseline variability is too high for a scan recommendation.'}
    $best=$null;$seen=@()
    foreach($candidate in @($Guide.ScanResults)){
        $core=ConvertTo-PCClockInteger $candidate.CoreMHz
        $increment=[long]$core-[long]$Guide.Clock.CoreMHz
        if($increment -notin @(15,30,45) -or $core -in $seen){throw 'Invalid or duplicate scan candidate.'}
        $seen+=$core
        Assert-PCClockGuideBatch $Guide $candidate.Records $core
        Assert-PCGpuScanBatch $Guide $candidate.Records
        $stats=Get-PCGroupStats $candidate.Records
        if($stats.SpreadPercent -le 5 -and $stats.Min -gt $base.Max -and ($null -eq $best -or $stats.Median -gt $best.Median)){
            $best=[pscustomobject]@{CoreMHz=$core;Median=$stats.Median;Records=@($candidate.Records)}
        }
    }
    $best
}
function Complete-PCGpuAutoScanBatch($Guide,$Records,[string]$Journal,[string]$Path) {
    $baseline=$Guide.Phase -eq 'RunningBaseline'
    try{
        Assert-PCGpuAutoScan $Guide
        Assert-PCGpuScanBatch $Guide $Records
        Complete-PCClockGuide $Guide $Records $Journal $Path
        if($baseline){
            $Guide.Summary='Baseline complete. Review the bounded core scan: +15, +30 and +45 MHz above the starting offset, three runs each. Original offsets are restored when the scan finishes.'
            if(@($Guide.Before | ForEach-Object {$_.Frames} | Where-Object {$_.CPUWarning}).Count){$Guide.Summary+=' CPU temperatures were unavailable in some or all samples. GPU temperature checks remain active; CPU thermal protection cannot cover missing readings.'}
            Save-PCClockGuide $Guide $Path;return
        }
        $Guide.ScanResults=@($Guide.ScanResults)+@([pscustomobject]@{CoreMHz=$Guide.TargetCore;Records=@($Records)})
        $stats=Get-PCGroupStats $Records;$base=Get-PCGroupStats $Guide.Before
        $stopEarly=$stats.SpreadPercent -gt 5 -or $stats.Median -lt $base.Median
        if(@($Guide.ScanResults).Count -lt 3 -and -not $stopEarly){
            $expected=[int]$Guide.Clock.CoreMHz+15*@($Guide.ScanResults).Count
            if($Guide.TargetCore -ne $expected){throw 'GPU scan step sequence is inconsistent.'}
            $null=Assert-PCClockGuideJournal $Guide $Journal
            $clock=Assert-PCClockGuideLive $Guide $Guide.TargetCore
            $Guide.TargetCore=[int]$Guide.TargetCore+15
            Assert-PCGpuAutoScan $Guide
            # Persist the impending step before any write. A restart requires recovery.
            $Guide.Phase='Applying';$Guide.Summary="Applying scan step $(@($Guide.ScanResults).Count+1)/3; core offset $($Guide.TargetCore) MHz."
            Save-PCClockGuide $Guide $Path
            $null=Set-PCGpuClockOffsets $clock $Guide.TargetCore $Guide.Clock.MemoryMHz $Journal
            $Guide.Phase='RunningAfter';$Guide.Summary="Testing scan step $(@($Guide.ScanResults).Count+1)/3 at core offset $($Guide.TargetCore) MHz. Cancel attempts restoration."
            Save-PCClockGuide $Guide $Path;return
        }
        $best=if(-not $stopEarly){Get-PCGpuScanRecommendation $Guide}else{$null}
        Restore-PCClockGuide $Guide $Journal $Path
        $Guide.ScanFinished=$true
        $Guide.RecommendedCore=if($best){$best.CoreMHz}else{$null}
        $lines=@('Scan finished. Starting core and memory offsets restored and read back.')
        foreach($candidate in @($Guide.ScanResults)){
            $s=Get-PCGroupStats $candidate.Records
            $lines+=('Core {0} MHz: median {1:N1} draws/s; spread {2:N1}%; change {3:+0.0;-0.0;0.0}%.' -f $candidate.CoreMHz,$s.Median,$s.SpreadPercent,(100*($s.Median/$base.Median-1)))
        }
        $lines+=if($best){"Candidate: core offset $($best.CoreMHz) MHz; memory $($Guide.Clock.MemoryMHz) MHz. Use Review recommended offset to apply it explicitly. Repeat and test your games before deciding to keep it."}else{'Keep the starting settings. No recommendation: the scan was noisy, regressed, or did not show a clear improvement over the baseline.'}
        if(@($Guide.Before | ForEach-Object {$_.Frames} | Where-Object {$_.CPUWarning}).Count){$lines+='CPU temperature coverage was incomplete or unavailable. No CPU thermal assessment is provided.'}
        $lines+='This short shader scan does not detect every artifact, memory error or crash risk, and does not establish stability or game FPS.'
        $Guide.ScanSummary=$lines -join "`n";$Guide.Summary=$Guide.ScanSummary
        Save-PCClockGuide $Guide $Path
    }catch{
        $Guide.ScanFinished=$false;$Guide.RecommendedCore=$null
        if($Guide.Phase -ne 'Restored'){Stop-PCClockGuide $Guide $Journal $Path $_.Exception.Message}
        else{Save-PCClockGuide $Guide $Path}
        throw
    }
}
function Apply-PCGpuScanRecommendation($Guide,[string]$Journal,[string]$Path) {
    if($Guide.Phase -ne 'Restored' -or $Guide.ScanFinished -ne $true -or $null -eq $Guide.RecommendedCore){throw 'Complete and restore a scan before applying its recommendation.'}
    if(Test-Path -LiteralPath $Journal){throw 'Restore the existing clock recovery record first.'}
    # Recompute from saved measurements; a stored target alone never authorizes a write.
    $best=Get-PCGpuScanRecommendation $Guide
    if(-not $best -or $best.CoreMHz -ne $Guide.RecommendedCore){throw 'The saved scan does not support this recommended offset.'}
    $clock=Assert-PCClockGuideLive $Guide $Guide.Clock.CoreMHz
    $Guide.TargetCore=$best.CoreMHz;$Guide.After=@($best.Records)
    $Guide.Phase='Applying';Save-PCClockGuide $Guide $Path
    try{
        $null=Set-PCGpuClockOffsets $clock $Guide.TargetCore $Guide.Clock.MemoryMHz $Journal
        $Guide.Phase='Decision';$Guide.Summary="Recommended core offset $($Guide.TargetCore) MHz applied and read back. Choose Keep or Restore. The earlier scan is not proof of stability.";Save-PCClockGuide $Guide $Path
    }catch{Stop-PCClockGuide $Guide $Journal $Path $_.Exception.Message;throw}
}
