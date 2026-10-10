# Saved CPU measurements only; this module never probes or changes hardware.
function Get-PCCpuResultNumber($Value) {
    $number=0.0
    if($null -ne $Value -and [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)){return $number}
}
function Get-PCCpuResultBatches($History) {
    foreach($group in @($History | Where-Object {$_.BatchId -and $_.Test -eq 'SHA256-1MiB-parallel-60s-v1'} | Group-Object BatchId)){
        $runs=@($group.Group | Sort-Object RunIndex);$last=$runs[-1]
        $reasons=[Collections.Generic.List[string]]::new()
        if($runs.Count -ne 3 -or (($runs.RunIndex | Sort-Object) -join ',') -ne '1,2,3'){$reasons.Add('Three distinct runs (1, 2 and 3) are required.')}
        $rates=@();$temps=@()
        foreach($run in $runs){
            $rate=Get-PCCpuResultNumber $run.MiBPerSecond
            $seconds=Get-PCCpuResultNumber $run.Seconds
            if($run.Completed -isnot [bool] -or -not $run.Completed -or $run.StopReason -or $null -eq $rate -or $rate -le 0){$reasons.Add('A run is incomplete or has no valid score.')}else{$rates+=$rate}
            if($null -eq $seconds -or $seconds -lt 54 -or $seconds -gt 66){$reasons.Add('Recorded duration is outside the 60-second test tolerance.')}
            foreach($field in @('CPUName','Runtime','Workers','Plan')){
                if([string]::IsNullOrWhiteSpace([string]$run.$field) -or [string]$run.$field -cne [string]$last.$field){$reasons.Add("Missing or mixed $field metadata.")}
            }
            $workers=Get-PCCpuResultNumber $run.Workers
            if($null -eq $workers -or $workers -le 0 -or $workers -ne [math]::Floor($workers)){$reasons.Add('Worker count is invalid.')}
            if((Get-PCPowerSignature $run.PowerStateAtStart) -cne (Get-PCPowerSignature $last.PowerStateAtStart)){$reasons.Add('Settings differ between runs.')}
            if(-not $run.PowerStateAtEnd -or (Get-PCPowerSignature $run.PowerStateAtStart) -cne (Get-PCPowerSignature $run.PowerStateAtEnd)){$reasons.Add('Run-boundary settings are missing or changed.')}
            $temp=Get-PCCpuResultNumber $run.PeakCPU
            if($null -ne $temp -and $temp -gt 0 -and $temp -lt 125){$temps+=$temp}
        }
        $stats=$null
        if($rates.Count){
            $sorted=@($rates | Sort-Object);$mid=[int][math]::Floor($sorted.Count/2);$median=$sorted[$mid]
            if($sorted.Count%2 -eq 0){$median=$sorted[$mid-1]+($sorted[$mid]-$sorted[$mid-1])/2}
            $spread=100*(($sorted[-1]-$sorted[0])/$median)
            if([double]::IsInfinity($spread)){$reasons.Add('Score range is invalid.');$spread=$null}
            $stats=[pscustomobject]@{Count=$rates.Count;Median=$median;Min=$sorted[0];Max=$sorted[-1];SpreadPercent=$spread}
        }
        $peak=if($temps.Count){($temps | Measure-Object -Maximum).Maximum}else{$null}
        $reasons=@($reasons | Select-Object -Unique)
        [pscustomobject]@{
            BatchId=$group.Name;Timestamp=$last.Timestamp;CPUName=$last.CPUName;Runtime=$last.Runtime;Workers=$last.Workers;Plan=$last.Plan
            Label=('{0} | {1}/3 runs | {2}' -f $last.Timestamp,$runs.Count,$(if($stats){'{0:N1} MiB/s' -f $stats.Median}else{'No score'}))
            Valid=($reasons.Count -eq 0);Reasons=$reasons;Stats=$stats;PeakCPU=$peak;TemperatureRuns=$temps.Count
            PowerState=$last.PowerStateAtStart;PowerText=(Get-PCRecordedCpuPowerContext $last.PowerStateAtStart);Runs=$runs
        }
    }
}
function Format-PCCpuResultBatch($Batch) {
    if(-not $Batch){return 'No saved CPU batch. Run the three-test CPU measurement above.'}
    $lines=@("$($Batch.Timestamp) | $($Batch.CPUName)")
    if($Batch.Stats){$lines+=('Median {0:N1} MiB/s | range {1:N1}-{2:N1} | spread {3:N1}%' -f $Batch.Stats.Median,$Batch.Stats.Min,$Batch.Stats.Max,$Batch.Stats.SpreadPercent)}
    $lines+=('Peak CPU: '+(Format-PCValue $Batch.PeakCPU 'C')+" | temperature recorded in $($Batch.TemperatureRuns)/3 runs")
    $lines+=$Batch.PowerText
    $lines+=if($Batch.Valid){'Three matching completed runs.'}else{'Comparison unavailable: '+($Batch.Reasons -join ' ')}
    $lines -join "`n"
}
function Get-PCCpuBatchComparison($Before,$After) {
    if(-not $Before -or -not $After){return}
    $reasons=[Collections.Generic.List[string]]::new();$notes=[Collections.Generic.List[string]]::new()
    if($Before.BatchId -eq $After.BatchId){$reasons.Add('Choose two different batches.')}
    foreach($batch in @($Before,$After)){if(-not $batch.Valid){$reasons.Add(($batch.Reasons -join ' '))}}
    foreach($field in @('CPUName','Runtime','Workers')){if([string]$Before.$field -cne [string]$After.$field){$reasons.Add("$field differs between batches.")}}
    $a=$Before.PowerState.CpuPower;$b=$After.PowerState.CpuPower
    if(-not (Test-PCRecordedCpuPower $a) -or -not (Test-PCRecordedCpuPower $b)){$reasons.Add('CPU power-limit context is unavailable. Run fresh batches to compare tuning.')}
    elseif($a.Identity -cne $b.Identity -or -not $a.BIOS -or $a.BIOS -cne $b.BIOS){$reasons.Add('CPU identity or BIOS differs or is missing.')}
    if($Before.Plan -cne $After.Plan){$notes.Add('Windows power plans differ; more than one setting may explain the change.')}
    $notes.Add('A: '+$Before.PowerText);$notes.Add('B: '+$After.PowerText)
    $notes.Add('Settings are sampled at run boundaries, not continuously. Firmware, cooling and background activity can affect results. A ten-second cooldown does not ensure equal starting temperatures.')
    $notes.Add('Peak temperature is the highest recorded CPU temperature across each batch, with coverage shown above. Different sensor coverage can affect peaks. This SHA-256 workload does not establish game FPS, stability or causation.')
    $delta=$null;$status='Comparison unavailable: '+($reasons -join ' ')
    if($reasons.Count -eq 0){
        $delta=100*($After.Stats.Median/$Before.Stats.Median-1)
        if([double]::IsInfinity($delta) -or [double]::IsNaN($delta)){$delta=$null;$reasons.Add('Score ratio is outside the supported numeric range.');$status='Comparison unavailable: score ratio is outside the supported numeric range.'}
        else{$status='Median throughput change (B minus A): {0:+0.0;-0.0;0.0}%.' -f $delta}
        if($Before.Stats.SpreadPercent -gt 5 -or $After.Stats.SpreadPercent -gt 5){$status+=' Inconclusive: a batch exceeds the 5% variability heuristic.'}
        elseif($Before.Stats.Min -le $After.Stats.Max -and $After.Stats.Min -le $Before.Stats.Max){$status+=' Run ranges overlap; the difference may be normal variation.'}
        else{$status+=' Run ranges do not overlap in these samples. Repeat to check reproducibility.'}
    }
    [pscustomobject]@{Schema=1;Kind='PCInsight.CpuBatchComparison';Created=(Get-Date).ToString('o');Before=$Before;After=$After;Comparable=($reasons.Count -eq 0);PercentChange=$delta;Reasons=@($reasons);Status=$status;Notes=@($notes)}
}
