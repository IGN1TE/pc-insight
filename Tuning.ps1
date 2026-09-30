function Invoke-PCNvidia([string[]]$Arguments) {
    $exe = @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exe) { throw 'Installed NVIDIA management tool not found. AMD/Intel power controls are not implemented.' }
    foreach ($arg in $Arguments) { if ($arg -notmatch '^[A-Za-z0-9_.=,:-]+$') { throw 'Invalid NVIDIA command argument.' } }
    $info = [Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.Arguments=$Arguments -join ' '
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try {
        $null=$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errorText=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'NVIDIA command timed out; its final hardware state must be checked.' }
        $stdout=$output.GetAwaiter().GetResult();$stderr=$errorText.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "NVIDIA rejected the request: $stderr $stdout" }
        $stdout
    } finally { $process.Dispose() }
}
function Convert-PCWatts($text) {
    $n=0.0
    if ([double]::TryParse(([string]$text).Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -and -not [double]::IsNaN($n) -and -not [double]::IsInfinity($n) -and $n -gt 0) { return $n }
    return $null
}
function Get-PCPowerDevices {
    $raw=Invoke-PCNvidia @('--query-gpu=uuid,name,driver_version,power.limit,power.default_limit,power.min_limit,power.max_limit','--format=csv,noheader,nounits')
    foreach ($row in ($raw -split "`r?`n" | Where-Object { $_.Trim() } | ConvertFrom-Csv -Header UUID,Name,Driver,Current,Default,Min,Max)) {
        $uuid=$row.UUID.Trim();$current=Convert-PCWatts $row.Current;$min=Convert-PCWatts $row.Min;$max=Convert-PCWatts $row.Max
        $available=$uuid -match '^GPU-[a-fA-F0-9-]+$' -and $null -ne $current -and $null -ne $min -and $null -ne $max -and $min -le $current -and $current -le $max
        [pscustomobject]@{UUID=$uuid;Name=$row.Name.Trim();Driver=$row.Driver.Trim();Current=$current;Default=(Convert-PCWatts $row.Default);Min=$min;Max=$max;Available=$available
            Label=($row.Name.Trim()+' · '+$uuid);Status=$(if($available){'Power range reported; write permission/support is not yet verified.'}else{'Power limits unavailable; controls disabled.'})}
    }
}
function Get-PCCpuPowerTestContext {
    try {
        if(-not (Get-Command Get-PCCpuPowerHardware -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'CpuPowerNative.ps1')}
        if(-not (Get-Command Test-PCRecordedCpuPower -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'CpuPowerMetadata.ps1')}
        $read=Get-PCCpuPowerHardware
        if(-not $read){throw 'CPU package power reader returned no metadata.'}
        # Read availability is independent of write support: locked or disabled
        # limits are still useful benchmark context when the raw read is complete.
        $context=$read | Select-Object Name,Identity,ProcessorId,BIOS,BootId,RawLimitHex,RawUnitsHex,Supported,Reason,PL1Watts,PL2Watts,Locked,PL1Enabled,PL2Enabled
        $context | Add-Member NoteProperty Available $true
        $context | Add-Member NoteProperty Timestamp (Get-Date).ToString('o')
        if(-not (Test-PCRecordedCpuPower $context)){
            $reason=if($read.Reason){[string]$read.Reason}else{'CPU package power reader returned incomplete or invalid metadata.'}
            throw $reason
        }
        return $context
    } catch {
        return [pscustomobject]@{Available=$false;Reason=$_.Exception.Message;Timestamp=(Get-Date).ToString('o')}
    }
}
function Get-PCTuningCapabilities {
    $devices=@();$issue=$null
    try {$devices=@(Get-PCPowerDevices)}catch{$issue=$_.Exception.Message}
    $clocks=@();$clockIssue=$null
    try{
        if(-not (Get-Command Get-PCClockDevices -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'GpuOverclock.ps1')}
        $clocks=@(Get-PCClockDevices|Select-Object UUID,Name,Driver,Available,CoreMHz,MemoryMHz,Issue)
    }catch{$clockIssue=$_.Exception.Message}
    $cpuPower=Get-PCCpuPowerTestContext
    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Devices=$devices;Issue=$issue;ClockOffsets=$clocks;ClockIssue=$clockIssue;CpuPower=$cpuPower;CPU='CPU package power support and recovery are checked on the CPU tuning page. Clock and voltage writes are not implemented.';GPU='NVIDIA power-limit reductions and capability-gated manual P0 clock offsets. Use Detect clock support separately. Voltage and AMD/Intel writes: not implemented.';RAM='XMP/EXPO and timing writes: not implemented.'}
}
function Get-PCDeviceById([string]$UUID) {
    if ($UUID -notmatch '^GPU-[a-fA-F0-9-]+$') { throw 'Invalid GPU identity.' }
    $matches=@(Get-PCPowerDevices | Where-Object UUID -eq $UUID)
    if ($matches.Count -ne 1 -or -not $matches[0].Available) { throw 'Selected GPU or its power limits are no longer available.' }
    $matches[0]
}
function Read-PCPowerJournal([string]$Path) {
    $j=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j.Schema -ne 1 -or $j.UUID -notmatch '^GPU-[a-fA-F0-9-]+$' -or $null -eq (Convert-PCWatts $j.OriginalWatts)) { throw 'Power recovery record is invalid. No hardware changes were made.' }
    $j
}
function Set-PCPowerAndVerify([string]$UUID,[double]$Watts) {
    $live=Get-PCDeviceById $UUID
    if ([double]::IsNaN($Watts) -or [double]::IsInfinity($Watts) -or $Watts -lt $live.Min -or $Watts -gt $live.Max) { throw 'Requested limit is outside the GPU-reported range.' }
    $value=$Watts.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $null=Invoke-PCNvidia @('-i',$UUID,'-pl',$value)
    $read=Get-PCDeviceById $UUID
    if ([math]::Abs($read.Current-$Watts) -gt 0.5) { throw "Read-back mismatch: requested $Watts W, reported $($read.Current) W." }
    $read
}
function Set-PCPowerReduction($Selected,[ValidateSet(80,90)][int]$Percent,[string]$JournalPath,[string]$BaselinePath,$Baseline) {
    $live=Get-PCDeviceById $Selected.UUID
    if ([math]::Abs($live.Current-$Selected.Current) -gt 0.5) { throw 'GPU limit changed since detection. Refresh compatibility before applying.' }
    $journal=$null
    if(Test-Path -LiteralPath $JournalPath){
        $journal=Read-PCPowerJournal $JournalPath
        if($journal.UUID -ne $live.UUID){throw 'Restore the previously changed GPU before tuning another GPU.'}
    }
    $original=$live.Current;if($journal){$original=[double]$journal.OriginalWatts}
    $target=[math]::Round($original*$Percent/100,2)
    if($target -lt $live.Min -or $target -gt $live.Max -or $target -gt $live.Current){throw 'This preset is outside the permitted range or would raise the current limit. Restore first or choose another reduction.'}
    if([math]::Abs($target-$live.Current) -le 0.5){return "Already at $($live.Current) W; no change made."}
    if(-not $journal){
        Save-JsonAtomic $Baseline $BaselinePath
        $journal=[pscustomobject]@{Schema=1;UUID=$live.UUID;Name=$live.Name;OriginalWatts=$original;Created=(Get-Date).ToString('o');LastRequested=$target}
    }else{$journal.LastRequested=$target}
    Save-JsonAtomic $journal $JournalPath
    try {
        $verified=Set-PCPowerAndVerify $live.UUID $target
        "Applied and verified $($verified.Current) W to $($live.Name). Original $original W is saved. Run the same GPU benchmark, then compare with baseline."
    }catch{
        $problem=$_.Exception.Message
        try { $null=Set-PCPowerAndVerify $live.UUID $live.Current; $recovery='Previous limit restored and verified.' }
        catch { $recovery='Automatic recovery could not be verified. Use Restore saved GPU limit; the recovery record has been retained.' }
        throw "$problem $recovery"
    }
}
function Restore-PCPower([string]$JournalPath) {
    if(-not (Test-Path -LiteralPath $JournalPath)){throw 'No saved GPU power change exists.'}
    $j=Read-PCPowerJournal $JournalPath
    $verified=Set-PCPowerAndVerify $j.UUID ([double]$j.OriginalWatts)
    Remove-Item -LiteralPath $JournalPath -ErrorAction Stop
    "Restored and verified $($verified.Current) W on $($verified.Name)."
}
function Get-PCComparableGroups($records) {
    @($records | Where-Object {$_.BatchId -and $_.Completed -ne $false -and -not $_.StopReason -and (Get-PCResultRate $_) -gt 0} |
        Group-Object { @($_.BatchId,$_.Test,$_.CPUName,$_.Runtime,$_.Workers,$_.Renderer,$_.DriverVersion,$_.MemoryConfig,$_.Plan,(Get-PCPowerSignature $_.PowerStateAtStart)) -join '|' } |
        Where-Object { $_.Count -eq 3 -and @($_.Group.RunIndex | Select-Object -Unique).Count -eq 3 } |
        Sort-Object {$_.Group[-1].Timestamp})
}
function Get-PCBatchSensorPeaks($records,$sessions,[string]$Name,[string]$Type) {
    foreach($record in $records){
        $session=$sessions | Where-Object {$_.Timestamp -eq $record.Timestamp -and $_.Test -eq $record.Test} | Select-Object -First 1
        if(-not $session){continue}
        $gpu=$record.Test -like 'OpenGL-*'
        $values=@($session.Frames | ForEach-Object {$_.Sensors} | Where-Object {
            $_.Name -eq $Name -and $_.Type -eq $Type -and $null -ne $_.Value -and
            (($gpu -and $_.Parent -match '^/gpu' -and $_.HardwareName -eq $record.GPUName) -or (-not $gpu -and $_.Parent -match '^/(intelcpu|amdcpu)/'))
        } | ForEach-Object {[double]$_.Value})
        if($values.Count){($values | Measure-Object -Maximum).Maximum}
    }
}
function Get-PCMedian($numbers) {
    $sorted=@($numbers | Sort-Object);if(-not $sorted.Count){return $null}
    $i=[int][math]::Floor($sorted.Count/2)
    if($sorted.Count%2){return $sorted[$i]}
    ($sorted[$i-1]+$sorted[$i])/2
}
function Get-PCBaselineComparison($Baseline,$History,$Sessions) {
    if(-not $Baseline){return 'Save a baseline after a complete three-run batch. Apply a reviewed change, then repeat the same batch.'}
    $lines=[Collections.Generic.List[string]]::new();$lines.Add("Saved baseline: $($Baseline.Created)")
    $beforeGroups=@(Get-PCComparableGroups $Baseline.Benchmarks)
    $afterGroups=@(Get-PCComparableGroups @($History | Where-Object {$_.Timestamp -gt $Baseline.Created}))
    if(-not $beforeGroups.Count){return "Saved baseline: $($Baseline.Created)`n`nINSUFFICIENT BASELINE: no complete, matching three-run batch was saved. Restore original settings, run a batch, then save the baseline. Individual test results remain in history."}
    if(-not $afterGroups.Count){return "Saved baseline: $($Baseline.Created)`n`nBaseline contains $($beforeGroups.Count) complete batch(es). No complete three-run batch after this baseline yet. Repeat the same batch after a reviewed change; a single run is not used for a tuning verdict."}
    foreach($after in @($afterGroups | Group-Object {$_.Group[-1].Test} | ForEach-Object {$_.Group[-1]})){
        $current=$after.Group[-1]
        $matches=@($beforeGroups | Where-Object {$null -ne (Get-PCPreviousMatch $current @($_.Group[-1]))})
        if(-not $matches.Count){$lines.Add("$($current.Test): no compatible complete baseline batch. Test revisions and hardware/driver requirements must match.");continue}
        $before=$matches[-1];$prior=$before.Group[-1];$a=Get-PCGroupStats $before.Group;$b=Get-PCGroupStats $after.Group
        $delta=100*($b.Median/$a.Median-1)
        $lines.Add(("{0} — 3 baseline + 3 new runs`nMedian: {1:N1} → {2:N1} {3} ({4:+0.0;-0.0;0.0}%).`nSpread: {5:N1}% → {6:N1}%." -f $current.Test,$a.Median,$b.Median,(Get-PCResultUnit $current),$delta,$a.SpreadPercent,$b.SpreadPercent))
        $lines.Add('Baseline test settings: '+(Get-PCPowerSignature $prior.PowerStateAtStart))
        $lines.Add('New test settings: '+(Get-PCPowerSignature $current.PowerStateAtStart))
        $lines.Add('Baseline '+(Get-PCRecordedCpuPowerContext $prior.PowerStateAtStart))
        $lines.Add('New '+(Get-PCRecordedCpuPowerContext $current.PowerStateAtStart))
        $unknown=(Get-PCPowerSignature $prior.PowerStateAtStart) -like 'GPU power limits unavailable*' -or (Get-PCPowerSignature $current.PowerStateAtStart) -like 'GPU power limits unavailable*'
        if($a.SpreadPercent -gt 5 -or $b.SpreadPercent -gt 5){$lines.Add('INCONCLUSIVE: at least one batch exceeds the 5% variability heuristic. No tuning gain or loss is established.')}
        elseif($prior.Plan -ne $current.Plan){$lines.Add('INCONCLUSIVE FOR A SINGLE CHANGE: Windows power plans differ between batches.')}
        elseif($unknown){$lines.Add('SETTINGS COVERAGE INCOMPLETE: GPU power limits were unavailable for at least one batch. No controlled tuning conclusion is established.')}
        elseif($current.Test -notlike 'OpenGL-*' -and (-not (Test-PCRecordedCpuPower $prior.PowerStateAtStart.CpuPower) -or -not (Test-PCRecordedCpuPower $current.PowerStateAtStart.CpuPower))){$lines.Add('SETTINGS COVERAGE INCOMPLETE: CPU limits unavailable for at least one batch. No controlled CPU tuning conclusion is established.')}
        elseif($a.Min -le $b.Max -and $b.Min -le $a.Max){$lines.Add('NO CLEAR SEPARATION: observed throughput ranges overlap. Treat the difference as inconclusive.')}
        elseif($delta -lt 0){$lines.Add('LOWER MEASURED THROUGHPUT: all three new scores are below the baseline range. Repeat to check reproducibility before attributing this to the setting.')}
        else{$lines.Add('HIGHER MEASURED THROUGHPUT: all three new scores are above the baseline range. Repeat to check reproducibility before attributing this to the setting.')}
        $power='CPU Package';$temp='CPU Package';if($current.Test -like 'OpenGL-*'){$power='GPU Package';$temp='GPU Core'}
        $oldPower=@(Get-PCBatchSensorPeaks $before.Group $Baseline.Sessions $power 'Power')
        $newPower=@(Get-PCBatchSensorPeaks $after.Group $Sessions $power 'Power')
        $oldTemp=@(Get-PCBatchSensorPeaks $before.Group $Baseline.Sessions $temp 'Temperature')
        $newTemp=@(Get-PCBatchSensorPeaks $after.Group $Sessions $temp 'Temperature')
        if($oldPower.Count -eq 3 -and $newPower.Count -eq 3){$lines.Add(('Median of sampled run power peaks: {0:N1} → {1:N1} W.' -f (Get-PCMedian $oldPower),(Get-PCMedian $newPower)))}
        else{$lines.Add('Power comparison unavailable: complete matching sensor records for all six runs are required.')}
        if($oldTemp.Count -eq 3 -and $newTemp.Count -eq 3){$lines.Add(('Median of sampled run temperature peaks: {0:N1} → {1:N1} C.' -f (Get-PCMedian $oldTemp),(Get-PCMedian $newTemp)))}
        else{$lines.Add('Temperature comparison unavailable: complete matching sensor records for all six runs are required.')}
        if($current.Test -like 'OpenGL-*' -and $oldPower.Count -eq 3 -and $newPower.Count -eq 3){
            $oldDevice=$prior.PowerStateAtStart.Devices | Where-Object Name -eq $current.GPUName | Select-Object -First 1
            $newDevice=$current.PowerStateAtStart.Devices | Where-Object UUID -eq $oldDevice.UUID | Select-Object -First 1
            if($oldDevice -and $newDevice -and $oldDevice.Current -gt 0 -and $newDevice.Current -gt 0){
                $lower=[math]::Min($oldDevice.Current,$newDevice.Current);$peak=(@($oldPower)+@($newPower)|Measure-Object -Maximum).Maximum
                if($peak -lt $lower){$lines.Add("POWER-LIMIT CONTEXT: highest sampled power was $([math]::Round($peak,1)) W, below both reported limits. These samples do not show either cap being reached; unsampled transients and other limits remain unknown.")}
            }
        }
    }
    $lines.Add('Settings are sampled at run boundaries, not continuously. Changes made and reversed between reads may not be detected.')
    $lines.Add('Three runs and a 5% variability threshold are heuristics, not statistical significance. Peak power is not energy use or efficiency. Cooling, background activity and unobserved settings can affect results. No changes are applied or restored by this comparison.')
    $lines -join "`n`n"
}
