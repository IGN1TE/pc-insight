# Local experiment records. Nothing in this module writes hardware settings.
function Assert-PCClockTrialHistoryRecord($Report) {
    $id=[guid]::Empty;$started=[datetimeoffset]::MinValue
    if(-not $Report -or $Report.Kind -ne 'PCInsight.GpuClockTrial' -or $Report.Schema -notin @(1,2) -or
        -not [guid]::TryParseExact([string]$Report.Id,'N',[ref]$id) -or
        -not [datetimeoffset]::TryParse([string]$Report.Started,[ref]$started) -or
        $Report.Device.UUID -notmatch '^GPU-[a-fA-F0-9-]+$' -or [string]::IsNullOrWhiteSpace($Report.Device.Driver) -or
        $Report.State -notin @('Completed','Stopped','RecoveryRequired','Interrupted')){
        throw 'Saved clock trial has an invalid identity or state.'
    }
    if($Report.Schema -eq 2 -and $Report.RunCount -notin @(1,3)){throw 'Saved clock trial has an invalid run count.'}
    foreach($value in @($Report.Device.CoreMHz,$Report.Device.MemoryMHz,$Report.Requested.CoreMHz,$Report.Requested.MemoryMHz)){$null=ConvertTo-PCClockInteger $value}
}
function Save-PCClockTrialHistory($Report,[string]$Folder) {
    Assert-PCClockTrialHistoryRecord $Report
    $null=[IO.Directory]::CreateDirectory($Folder)
    $path=Join-Path $Folder ($Report.Id+'.json')
    if(Test-Path -LiteralPath $path){
        $old=Read-PCClockTrialReport $path;Assert-PCClockTrialHistoryRecord $old
        if($old.Id -ne $Report.Id -or $old.Started -ne $Report.Started -or $old.Device.UUID -ne $Report.Device.UUID -or
            $old.Device.Driver -ne $Report.Device.Driver -or $old.Device.CoreMHz -ne $Report.Device.CoreMHz -or $old.Device.MemoryMHz -ne $Report.Device.MemoryMHz -or
            $old.Requested.CoreMHz -ne $Report.Requested.CoreMHz -or $old.Requested.MemoryMHz -ne $Report.Requested.MemoryMHz){throw 'A different saved experiment already uses this identity. Existing history was retained.'}
        # An older running checkpoint must not replace a final recovery outcome.
        if($Report.State -eq 'Interrupted' -and $old.State -ne 'Interrupted'){return}
    }
    Save-PCClockJournal $Report $path
}
function Get-PCClockTrialHistoryFolder([string]$ReportPath) {
    Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReportPath))) 'gpu-clock-trials'
}
function Protect-PCPreviousClockTrial([string]$ReportPath) {
    if(Test-Path -LiteralPath $ReportPath){
        $previous=Read-PCClockTrialReport $ReportPath
        Save-PCClockTrialHistory $previous (Get-PCClockTrialHistoryFolder $ReportPath)
    }
}
function Get-PCClockTrialHistory([string]$Folder,[ValidateRange(1,200)][int]$Limit=50) {
    $entries=[Collections.Generic.List[object]]::new();$issues=[Collections.Generic.List[string]]::new()
    if(Test-Path -LiteralPath $Folder){
        # Keep every archive on disk. The picker only loads the most recent 50.
        $files=@(Get-ChildItem -LiteralPath $Folder -Filter '*.json' -File -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending)
        foreach($file in $files){
            if($file.BaseName -notmatch '^[a-fA-F0-9]{32}$'){continue}
            try{
                if($file.Length -gt 1048576 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Archive is too large or is a linked file.'}
                $report=Read-PCClockTrialReport $file.FullName;Assert-PCClockTrialHistoryRecord $report
                if($report.Id -ne $file.BaseName){throw 'Archive name does not match its experiment identity.'}
                $date=[datetimeoffset]::Parse($report.Started)
                $entries.Add([pscustomobject]@{Id=$report.Id;Started=$date;Report=$report;Label=('{0} | core {1}, memory {2} MHz | {3} | {4}' -f $date.ToLocalTime().ToString('yyyy-MM-dd HH:mm'),$report.Requested.CoreMHz,$report.Requested.MemoryMHz,$report.State,$report.Id.Substring(0,6))})
                if($entries.Count -ge $Limit){break}
            }catch{$issues.Add("Could not read $($file.Name): $($_.Exception.Message) File retained.")}
        }
    }
    [pscustomobject]@{Entries=@($entries.ToArray()|Sort-Object Started -Descending);Issues=@($issues.ToArray())}
}
function Assert-PCStoredClockTrialEnvironment($Environment,$Device) {
    if(-not $Environment -or $Environment.Plan -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$' -or
        $Environment.UUID -ne $Device.UUID -or $Environment.Driver -ne $Device.Driver -or
        $null -eq (Convert-PCWatts $Environment.PowerLimitWatts)){throw 'Recorded power-setting coverage is incomplete.'}
}
function Measure-PCStoredClockTrial($Report) {
    Assert-PCClockTrialHistoryRecord $Report
    if($Report.Schema -ne 2 -or $Report.RunCount -ne 3 -or $Report.State -ne 'Completed' -or $Report.Restoration -ne 'Verified'){
        throw 'Comparison requires completed three-run trials with recorded verified restoration.'
    }
    Assert-PCStoredClockTrialEnvironment $Report.Environment $Report.Device
    $summary=[pscustomobject]@{RunCount=3;BeforeSummary=$null;AfterSummary=$null;ChangePercent=$null;Comparison=$null;ComparisonReasons=@();Reference=$Report.BeforeRuns[0]}
    foreach($side in 'Before','After'){
        $runs=@($Report.($side+'Runs'))
        if($runs.Count -ne 3 -or (@($runs.RunIndex|Sort-Object) -join ',') -ne '1,2,3'){throw 'Three distinct runs are required at each setting.'}
        foreach($run in $runs){
            if($run.Eligible -ne $true){throw 'An excluded run cannot be used in a saved comparison.'}
            Assert-PCClockTrialMeasurement $run $Report.Device
            Assert-PCClockTrialComparable $summary.Reference $run
            $temperature=0.0
            if($null -eq $run.StartGpuC -or -not [double]::TryParse([string]$run.StartGpuC,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$temperature) -or
                [double]::IsNaN($temperature) -or [double]::IsInfinity($temperature) -or $temperature -le 0 -or $temperature -ge 85){throw 'Recorded starting temperature is invalid.'}
            foreach($context in @($run.EnvironmentBefore,$run.EnvironmentAfter)){
                Assert-PCStoredClockTrialEnvironment $context $Report.Device
                Assert-PCClockTrialEnvironment $Report.Environment $context
            }
        }
        $summary.($side+'Summary')=Get-PCClockTrialSummary $runs
    }
    # Recalculate from individual runs instead of trusting cached totals/verdicts.
    Complete-PCClockTrialComparison $summary
    $summary
}
function Compare-PCClockTrials($Reference,$Current) {
    $comparison=[pscustomobject]@{
        Schema=1;Kind='PCInsight.GpuClockTrialComparison';Created=[datetimeoffset]::Now.ToString('o')
        ReferenceId=$Reference.Id;CurrentId=$Current.Id;Compatible=$false;Quality='Unavailable';ChangePercent=$null
        Before=$null;After=$null;BaselineDriftPercent=$null;Reasons=@()
        Limitations='Saved shader experiments, not a current hardware check or a recommendation to apply settings. Three runs do not establish causation or statistical significance. Background activity, cooling and unrecorded settings can differ.'
    }
    try{
        if(-not $Reference -or -not $Current -or $Reference.Id -eq $Current.Id){throw 'Choose two different saved trials.'}
        $a=Measure-PCStoredClockTrial $Reference;$b=Measure-PCStoredClockTrial $Current
        if($Reference.Device.UUID -ne $Current.Device.UUID -or $Reference.Device.Name -ne $Current.Device.Name -or $Reference.Device.Driver -ne $Current.Device.Driver){throw 'The saved GPU or driver differs.'}
        if($Reference.Device.CoreMHz -ne $Current.Device.CoreMHz -or $Reference.Device.MemoryMHz -ne $Current.Device.MemoryMHz){throw 'Original baseline offsets differ between these experiments.'}
        Assert-PCClockTrialEnvironment $Reference.Environment $Current.Environment
        Assert-PCClockTrialComparable $a.Reference $b.Reference
        foreach($run in @($Current.BeforeRuns)+@($Current.AfterRuns)){Assert-PCClockTrialComparable $a.Reference $run}
        $comparison.Before=$a.AfterSummary;$comparison.After=$b.AfterSummary
        $comparison.ChangePercent=[math]::Round(100*($b.AfterSummary.Median/$a.AfterSummary.Median-1),2)
        $comparison.BaselineDriftPercent=100*($b.BeforeSummary.Median/$a.BeforeSummary.Median-1)
        $reasons=[Collections.Generic.List[string]]::new()
        foreach($reason in @($a.ComparisonReasons)){$reasons.Add('Trial A: '+$reason)}
        foreach($reason in @($b.ComparisonReasons)){$reasons.Add('Trial B: '+$reason)}
        if([math]::Abs($comparison.BaselineDriftPercent) -gt 5){$reasons.Add('Original-setting medians differ by more than the 5% comparison heuristic.')}
        if([math]::Abs($a.AfterSummary.MedianStartGpuC-$b.AfterSummary.MedianStartGpuC) -gt 5){$reasons.Add('Retest starting temperatures differ by more than the 5 C comparison heuristic.')}
        if($b.AfterSummary.Min -le $a.AfterSummary.Max -and $a.AfterSummary.Min -le $b.AfterSummary.Max){$reasons.Add('Retest ranges overlap between experiments.')}
        if($Reference.Requested.CoreMHz -eq $Current.Requested.CoreMHz -and $Reference.Requested.MemoryMHz -eq $Current.Requested.MemoryMHz){$reasons.Add('Both experiments requested the same offsets; this is repeatability, not a different tuning setting.')}
        if($comparison.ChangePercent -eq 0){$reasons.Add('Retest median difference rounds to 0.00%.')}
        $comparison.Reasons=@($reasons.ToArray());$comparison.Compatible=$true
        $comparison.Quality=if($reasons.Count){'Inconclusive'}elseif($comparison.ChangePercent -gt 0){'Observed higher throughput in B'}else{'Observed lower throughput in B'}
    }catch{$comparison.ChangePercent=$null;$comparison.BaselineDriftPercent=$null;$comparison.Reasons=@($_.Exception.Message)}
    $comparison
}
function Format-PCClockTrialComparison($Comparison,$Reference,$Current) {
    if(-not $Reference -or -not $Current){return 'Choose two saved trials to compare their requested offsets and recorded results.'}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add("A: core $($Reference.Requested.CoreMHz), memory $($Reference.Requested.MemoryMHz) MHz | $($Reference.Started)")
    $lines.Add("B: core $($Current.Requested.CoreMHz), memory $($Current.Requested.MemoryMHz) MHz | $($Current.Started)")
    $lines.Add('Comparison: '+$Comparison.Quality)
    if($Comparison.Compatible){
        $lines.Add(('Retest medians A -> B: {0:N2} -> {1:N2} draws/s ({2:+0.00;-0.00;0.00}%).' -f $Comparison.Before.Median,$Comparison.After.Median,$Comparison.ChangePercent))
        $lines.Add(('Retest spread: {0:N2}% -> {1:N2}% | Original-setting median change: {2:+0.00;-0.00;0.00}%.' -f $Comparison.Before.SpreadPercent,$Comparison.After.SpreadPercent,$Comparison.BaselineDriftPercent))
    }
    foreach($reason in @($Comparison.Reasons)){$lines.Add($reason)}
    $lines.Add($Comparison.Limitations)
    $lines -join "`n"
}
function Get-PCSavedClockTrialOffsets($Report,$Device) {
    Assert-PCClockTrialHistoryRecord $Report
    if($Report.State -ne 'Completed' -or $Report.Restoration -ne 'Verified'){throw 'Only a completed trial with recorded verified restoration can supply offset inputs.'}
    Assert-PCClockDevice $Device $Report.Device.UUID
    if($Device.Driver -ne $Report.Device.Driver){throw 'Driver changed since this trial. Enter and review new values after detection.'}
    $core=ConvertTo-PCClockInteger $Report.Requested.CoreMHz;$memory=ConvertTo-PCClockInteger $Report.Requested.MemoryMHz
    Assert-PCClockTargets $Device $core $memory
    [pscustomobject]@{CoreMHz=$core;MemoryMHz=$memory}
}
