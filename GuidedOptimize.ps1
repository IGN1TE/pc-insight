# Guided GPU power reduction: no writes occur on startup or during baseline capture.
function New-PCGuide($Devices,[string]$Plan,[string]$JournalPath) {
    if(Test-Path -LiteralPath $JournalPath){throw 'Restore the existing saved GPU limit before starting a new guided run.'}
    $devices=@($Devices)
    if($devices.Count -ne 1 -or -not $devices[0].Available){throw 'Guided tuning currently requires exactly one NVIDIA GPU with readable power limits.'}
    $device=$devices[0]
    $target=[math]::Round($device.Current*0.9,2)
    if($target -lt $device.Min -or $target -gt $device.Max -or $device.Current-$target -le 0.5){throw 'A 90% reduction is not within this GPU reported limits.'}
    [pscustomobject]@{
        Schema=1;ID=[guid]::NewGuid().ToString();Created=(Get-Date).ToString('o')
        Phase='Ready';Device=$device;Plan=$Plan;TargetWatts=$target
        Before=@();After=@();Baseline=$null;Verdict=$null;Message='Compatibility ready. Start a fresh three-run baseline.'
    }
}
function Save-PCGuide($Guide,[string]$Path) {Save-JsonAtomic $Guide $Path}
function Read-PCGuide([string]$Path) {
    $g=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    $id=[guid]::Empty
    if($g.Schema -ne 1 -or -not [guid]::TryParse([string]$g.ID,[ref]$id) -or
       $g.Device.UUID -notmatch '^GPU-[a-fA-F0-9-]+$' -or
       $null -eq (Convert-PCWatts $g.Device.Current) -or
       $null -eq (Convert-PCWatts $g.TargetWatts) -or
       $g.Phase -notin @('Ready','RunningBaseline','Review','Applying','RunningAfter','Decision','Kept','Restored','Interrupted','RecoveryRequired')){
        throw 'Saved guided session is invalid. Use Tuning to inspect any pending recovery record.'
    }
    return $g
}
function Assert-PCGuideLiveState($Guide,[double]$ExpectedWatts) {
    $live=Get-PCDeviceById $Guide.Device.UUID
    if($live.Name -ne $Guide.Device.Name -or $live.Driver -ne $Guide.Device.Driver){throw 'GPU identity or driver changed. Start a fresh guided baseline.'}
    if([math]::Abs($live.Current-$ExpectedWatts) -gt 0.5){throw 'The GPU power limit changed outside this guided session.'}
    if((Get-ActivePlan) -ne $Guide.Plan){throw 'Windows power plan changed. Restore and start a fresh baseline.'}
    return $live
}
function Assert-PCGuideBatch($Guide,$Records,[double]$ExpectedWatts) {
    $rows=@($Records)
    if($rows.Count -ne 3){throw 'All three benchmark runs must complete.'}
    if(@($rows.BatchId|Select-Object -Unique).Count -ne 1 -or -not $rows[0].BatchId -or
       (@($rows.RunIndex|Sort-Object) -join ',') -ne '1,2,3'){throw 'Batch identity or run sequence is incomplete.'}
    $signatures=@()
    foreach($r in $rows){
        $rate=ConvertTo-PCInvariantNumber (Get-PCResultRate $r)
        if($r.Completed -ne $true -or $r.StopReason -or $r.Test -ne 'OpenGL-1280x720-256shader-b8-w5-30s-v2' -or
           $rate -eq '' -or [double]::Parse($rate,[Globalization.CultureInfo]::InvariantCulture) -le 0){
            throw 'The GPU test stopped or did not return a valid comparable score.'
        }
        if($r.GPUName -ne $Guide.Device.Name -or $r.Plan -ne $Guide.Plan){throw 'Benchmark renderer or Windows power plan does not match the selected GPU baseline.'}
        $devices=@($r.PowerStateAtStart.Devices|Where-Object UUID -eq $Guide.Device.UUID)
        if($r.PowerStateAtStart.Issue -or $devices.Count -ne 1 -or $null -eq (Convert-PCWatts $devices[0].Current) -or [math]::Abs($devices[0].Current-$ExpectedWatts) -gt 0.5){
            throw 'Recorded power settings do not match the guided test.'
        }
        if(-not @($r.Frames).Count -or @($r.Frames|Where-Object{$_.Issue}).Count){throw 'The test has missing sensor history or reported sensor issues.'}
        $signatures+= (@($r.Test,$r.CPUName,$r.Runtime,$r.Workers,$r.Renderer,$r.DriverVersion,$r.MemoryConfig,$r.Plan) -join '|')
    }
    if(@($signatures|Select-Object -Unique).Count -ne 1){throw 'Hardware or test configuration changed between runs.'}
    if(@($Guide.Before).Count){
        $prior=$Guide.Before[0]
        $signature=@($prior.Test,$prior.CPUName,$prior.Runtime,$prior.Workers,$prior.Renderer,$prior.DriverVersion,$prior.MemoryConfig,$prior.Plan) -join '|'
        if($signature -ne $signatures[0]){throw 'The retest configuration differs from the baseline.'}
    }
}
function Get-PCGuideVerdict($Guide) {
    Assert-PCGuideBatch $Guide $Guide.Before $Guide.Device.Current
    Assert-PCGuideBatch $Guide $Guide.After $Guide.TargetWatts
    $a=Get-PCGroupStats $Guide.Before;$b=Get-PCGroupStats $Guide.After
    $delta=100*($b.Median/$a.Median-1)
    $overlap=$a.Min -le $b.Max -and $b.Min -le $a.Max
    $title='No demonstrated benefit';$recommendation='Restore original limit recommended.'
    if($a.SpreadPercent -gt 5 -or $b.SpreadPercent -gt 5){$title='Inconclusive: high variability'}
    elseif(-not $overlap -and $delta -lt 0){$title='Lower measured throughput'}
    elseif(-not $overlap -and $delta -gt 0){$title='Higher measured throughput';$recommendation='Consider keeping only after checking the trade-off. Repeat to confirm.'}
    elseif($overlap){$title='Inconclusive: score ranges overlap'}
    [pscustomobject]@{
        Title=$title;Recommendation=$recommendation;PercentChange=$delta
        BeforeMedian=$a.Median;AfterMedian=$b.Median;BeforeSpread=$a.SpreadPercent;AfterSpread=$b.SpreadPercent
        Detail=Get-PCBaselineComparison $Guide.Baseline $Guide.After $Guide.After
    }
}
function Restore-PCGuide($Guide,[string]$JournalPath,[string]$GuidePath) {
    if(-not(Test-Path -LiteralPath $JournalPath)){
        # A record may already have been restored from Tuning; verify rather than invent recovery.
        $null=Assert-PCGuideLiveState $Guide $Guide.Device.Current
    }else{
        $journal=Read-PCPowerJournal $JournalPath
        if($journal.UUID -ne $Guide.Device.UUID -or [math]::Abs($journal.OriginalWatts-$Guide.Device.Current) -gt 0.5){throw 'Recovery record does not match this guided session. Inspect it in Tuning.'}
        $null=Restore-PCPower $JournalPath
    }
    $Guide.Phase='Restored';$Guide.Message='Original GPU limit restored and read-back verified.'
    Save-PCGuide $Guide $GuidePath
}
function Stop-PCGuide($Guide,[string]$JournalPath,[string]$GuidePath,[string]$Reason) {
    if(-not $Guide){return}
    if($Guide.Phase -in @('Applying','RunningAfter')){
        try{Restore-PCGuide $Guide $JournalPath $GuidePath;$Guide.Message="$Reason Original limit restored and verified."}
        catch{$Guide.Phase='RecoveryRequired';$Guide.Message="$Reason Restoration could not be verified: $($_.Exception.Message)"}
    }else{$Guide.Phase='Interrupted';$Guide.Message="$Reason No guided hardware change was applied."}
    Save-PCGuide $Guide $GuidePath
}
function Apply-PCGuide($Guide,[string]$JournalPath,[string]$BaselinePath,[string]$GuidePath) {
    if($Guide.Phase -ne 'Review'){throw 'Complete the baseline before applying a preset.'}
    if(Test-Path -LiteralPath $JournalPath){throw 'An existing recovery record must be resolved before applying.'}
    Assert-PCGuideBatch $Guide $Guide.Before $Guide.Device.Current
    if((Get-PCGroupStats $Guide.Before).SpreadPercent -gt 5){throw 'Baseline variability exceeds 5%; repeat before applying.'}
    $live=Assert-PCGuideLiveState $Guide $Guide.Device.Current
    $Guide.Phase='Applying';$Guide.Message='Saving recovery information and applying the reviewed power reduction.'
    try{
        Save-PCGuide $Guide $GuidePath
        $null=Set-PCPowerReduction $live 90 $JournalPath $BaselinePath $Guide.Baseline
        $null=Assert-PCGuideLiveState $Guide $Guide.TargetWatts
        $Guide.Phase='RunningAfter';$Guide.Message='Reduction verified. Running the same three-test batch.'
        Save-PCGuide $Guide $GuidePath
    }catch{
        $reason=$_.Exception.Message
        Stop-PCGuide $Guide $JournalPath $GuidePath $reason
        throw $reason
    }
}
function Resume-PCGuideState($Guide,[string]$JournalPath) {
    if($Guide.Phase -in @('Ready','RunningBaseline','Review','Applying','RunningAfter')){
        $Guide.Phase=if(Test-Path -LiteralPath $JournalPath){'RecoveryRequired'}else{'Interrupted'}
        $Guide.Message='Previous workflow was interrupted. No settings were changed on startup. Inspect any recovery record before starting again.'
    }
    return $Guide
}
