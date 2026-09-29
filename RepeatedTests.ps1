function Get-PCPowerSignature($state) {
    if (-not $state -or $state.Issue -or -not @($state.Devices).Count) { return 'GPU power limits unavailable' }
    (@($state.Devices | Sort-Object UUID | ForEach-Object { "$($_.UUID)=$($_.Current)W" })) -join '; '
}
function Invoke-PCRepeatedTest([ValidateSet('longcpu','memory','gpu')][string]$Kind) {
    $batch=[guid]::NewGuid().ToString();$results=[Collections.Generic.List[object]]::new()
    for($run=1;$run -le 3;$run++) {
        [pscustomobject]@{Kind='BatchStatus';Value="Run $run of 3 · $Kind"}
        $before=Get-PCTuningCapabilities;$plan=Get-ActivePlan;$result=$null
        try {
            $invoke={ if($Kind -eq 'longcpu'){Invoke-PCSensorSession -WithLoad -DurationSeconds 60}else{Invoke-PCExtendedTest $Kind} }
            & $invoke | ForEach-Object {
                if($_.Kind -eq 'Result'){$result=$_.Value}
                elseif($_.Kind -eq 'Progress'){[pscustomobject]@{Kind='Progress';Value=((($run-1)*100+$_.Value)/3)}}
                else {$_}
            }
        } catch {
            $result=[pscustomobject]@{Test="Batch-$Kind-failed";Timestamp=(Get-Date).ToString('o');Seconds=0;Workers=0;Runtime=[Environment]::Version.ToString();Completed=$false;StopReason=$_.Exception.Message;MiBPerSecond=$null;GpuFramesPerSecond=$null;PeakCPU=$null;Frames=@()}
        }
        if(-not $result){throw 'No result from repeated test.'}
        $after=Get-PCTuningCapabilities;$endPlan=Get-ActivePlan
        if((Get-PCPowerSignature $before) -ne (Get-PCPowerSignature $after) -or $plan -ne $endPlan){
            $result.Completed=$false;$result.StopReason='Reported power settings changed during this run. Batch stopped; score excluded.';$result.MiBPerSecond=$null
            if($result.PSObject.Properties['GpuFramesPerSecond']){$result.GpuFramesPerSecond=$null}
        }
        $result | Add-Member NoteProperty BatchId $batch
        $result | Add-Member NoteProperty RunIndex $run
        $result | Add-Member NoteProperty RunCount 3
        $result | Add-Member NoteProperty PowerStateAtStart $before
        $result | Add-Member NoteProperty Plan $plan
        $results.Add($result)
        if(-not $result.Completed -or $result.StopReason){break}
        if($run -lt 3){
            [pscustomobject]@{Kind='BatchStatus';Value="Run $run complete · 10-second cooldown"}
            for($pause=0;$pause -lt 10;$pause++){Start-Sleep -Seconds 1;[pscustomobject]@{Kind='Frame';Value=(Get-PCSensorFrame)}}
        }
    }
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{BatchResults=@($results.ToArray())}}
}
function Get-PCGroupStats($records) {
    $values=@($records | Where-Object {$_.Completed -ne $false -and -not $_.StopReason -and (Get-PCResultRate $_) -gt 0} | ForEach-Object {[double](Get-PCResultRate $_)} | Sort-Object)
    if(-not $values.Count){return $null}
    $middle=[int][math]::Floor($values.Count/2);$median=$values[$middle]
    if($values.Count%2 -eq 0){$median=($values[$middle-1]+$values[$middle])/2}
    [pscustomobject]@{Count=$values.Count;Median=$median;Min=$values[0];Max=$values[-1];SpreadPercent=100*($values[-1]-$values[0])/$median}
}
function Get-PCBatchReport($history) {
    $valid=@($history | Where-Object {$_.BatchId -and $_.Completed -ne $false -and -not $_.StopReason -and (Get-PCResultRate $_) -gt 0})
    if(-not $valid.Count){return 'Run a 3-run batch from Benchmark. Results will show the median and min–max spread; individual runs remain in history.'}
    $groups=@($valid | Group-Object { @($_.BatchId,$_.Test,$_.CPUName,$_.Runtime,$_.Workers,$_.Renderer,$_.DriverVersion,$_.MemoryConfig,$_.Plan,(Get-PCPowerSignature $_.PowerStateAtStart)) -join '|' } | Sort-Object {$_.Group[-1].Timestamp})
    $lines=[Collections.Generic.List[string]]::new()
    foreach($group in @($groups | Select-Object -Last 8)){
        $last=$group.Group[-1];$stats=Get-PCGroupStats $group.Group
        $lines.Add(("{0} | {1}`n{2}/3 matching runs · median {3:N1} {4}`nRange {5:N1}–{6:N1}; spread {7:N1}% of median.`n{8}" -f $last.Test,$last.Timestamp,$stats.Count,$stats.Median,(Get-PCResultUnit $last),$stats.Min,$stats.Max,$stats.SpreadPercent,(Get-PCPowerSignature $last.PowerStateAtStart)))
        if($stats.SpreadPercent -gt 5){$lines.Add('HIGH VARIABILITY: spread exceeds the 5% app heuristic. Tuning conclusions are inconclusive; inspect background activity and starting conditions before repeating.')}
        if($stats.Count -lt 3){$lines.Add('Incomplete or mixed-settings batch: collect three matching successful runs before comparing.')}
    }
    $latest=$groups[-1];$now=Get-PCGroupStats $latest.Group
    if($now.Count -eq 3){
        $current=$latest.Group[-1]
        $prior=@($groups | Where-Object { $_.Name -ne $latest.Name -and $_.Group[-1].Timestamp -lt $current.Timestamp -and (Get-PCGroupStats $_.Group).Count -eq 3 -and $null -ne (Get-PCPreviousMatch $current @($_.Group[-1])) } | Select-Object -Last 1)
        if($prior.Count){
            $old=Get-PCGroupStats $prior[0].Group;$delta=100*($now.Median/$old.Median-1)
            $lines.Add(('LATEST BATCH COMPARISON: median {0:N1} → {1:N1} {2} ({3:+0.0;-0.0;0.0}%).' -f $old.Median,$now.Median,(Get-PCResultUnit $current),$delta))
            $lines.Add('Earlier settings: '+(Get-PCPowerSignature $prior[0].Group[-1].PowerStateAtStart))
            $lines.Add('Latest settings: '+(Get-PCPowerSignature $current.PowerStateAtStart))
            if($prior[0].Group[-1].Plan -ne $current.Plan){$lines.Add('Windows power plans differ; this is not a controlled single-setting comparison.')}
            if($now.SpreadPercent -gt 5 -or $old.SpreadPercent -gt 5){$lines.Add('COMPARISON INCONCLUSIVE: at least one batch exceeds the 5% variability heuristic. The median difference is descriptive, not evidence of a tuning gain or loss.')}
            if($now.Min -le $old.Max -and $old.Min -le $now.Max){$lines.Add('Observed run ranges overlap. The difference may be normal variability.')}
            else{$lines.Add('Observed ranges do not overlap in these samples. Repeat to check reproducibility; three runs do not establish statistical significance.')}
        }else{$lines.Add('No earlier compatible complete batch. This batch records the initial measurements; check its variability before using it as a tuning baseline.')}
    }
    $lines.Add('Cooldown is fixed at 10 seconds, not a guarantee of equal starting temperature. Keep workload, cooling and background applications consistent. Medians reduce sensitivity to one outlier; these tests do not establish stability or causation.')
    $lines -join "`n`n"
}
