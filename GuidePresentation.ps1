# Presentation only: saved workflow results never stand in for live GPU readings.
function Format-PCGuideNumber($Value,[string]$Format='0.00') {
    if($null -eq $Value){return '--'}
    try{$number=[double]$Value}catch{return '--'}
    if([double]::IsNaN($number) -or [double]::IsInfinity($number)){return '--'}
    return $number.ToString($Format,[Globalization.CultureInfo]::InvariantCulture)
}
function Get-PCGuidePresentation($Guide,[bool]$JournalPending=$false,[string]$LoadIssue='') {
    $phase=if($Guide){[string]$Guide.Phase}else{'Not started'}
    $original=if($Guide){Format-PCGuideNumber $Guide.Device.Current '0.##'}else{'--'}
    $target=if($Guide){Format-PCGuideNumber $Guide.TargetWatts '0.##'}else{'--'}
    $view=[pscustomobject]@{
        Stage='Ready to begin';Tone='Neutral'
        NextAction='Scan PC, then check compatibility. Detection does not change settings.'
        KeepLabel="Keep $target W";RestoreLabel="Restore $original W"
        ResultTitle='Your comparison will appear here'
        RecommendationLabel='TEST RECOMMENDATION';Recommendation='Complete three baseline runs and three retests to compare results.'
        BeforeScore='--';AfterScore='--';Change='--'
        Detail='No completed comparison yet.'
        Recovery='No GPU recovery record is pending.'
    }
    switch($phase){
        'Ready' {$view.Stage='Step 1 complete: compatible GPU';$view.NextAction='Run the baseline: three GPU tests at the original power ceiling.'}
        'RunningBaseline' {$view.Stage='Step 2: measuring the baseline';$view.NextAction='Three tests are running. No guided setting change has been applied.'}
        'Review' {$view.Stage='Step 3: review the proposed change';$view.NextAction="Baseline complete. Review the change from $original W to $target W before applying and retesting."}
        'Applying' {$view.Stage='Step 3: applying the reviewed limit';$view.NextAction='Saving the original limit, applying the change and checking the driver read-back.'}
        'RunningAfter' {$view.Stage='Step 4: testing the reduced ceiling';$view.NextAction="The $target W ceiling was applied and verified. Three matching tests are running. Cancel will attempt restoration."}
        'Decision' {$view.Stage='Step 5: choose Keep or Restore';$view.Tone='Attention';$view.NextAction="The recommendation below has not changed your settings. Choose Restore $original W or Keep $target W to finish."}
        'Kept' {$view.Stage="You chose to keep $target W";$view.Tone='Success';$view.NextAction="The ceiling was verified when you chose Keep. Restore $original W remains available. This saved result is not a live GPU reading."}
        'Restored' {$view.Stage="Original limit restored: $original W";$view.Tone='Success';$view.NextAction='Restoration was read-back verified. No further action is needed for this guided run. This saved result is not a live GPU reading.'}
        'Interrupted' {$view.Stage='Guided run interrupted';$view.Tone='Attention';$view.NextAction='Check compatibility again to start a new run. No completed tuning result is claimed.'}
        'RecoveryRequired' {$view.Stage='Restoration needs attention';$view.Tone='Warning';$view.NextAction="Restoration has not been verified. Use Restore $original W and check the result before starting another run."}
    }
    if($JournalPending){
        $view.Recovery='The original GPU limit is saved for recovery. Choosing Keep or closing after Keep does not restore it.'
        if($phase -in @('Not started','Ready','RunningBaseline','Review','Restored','Interrupted')){
            $view.Stage='A GPU recovery record needs attention';$view.Tone='Warning'
            $view.NextAction='Open Tuning to inspect and restore the saved limit before starting a new guided run. The saved workflow does not confirm the current GPU setting.'
        }
    }elseif($phase -in @('Kept','Decision','RecoveryRequired')){
        $view.Recovery='The GPU recovery record is missing. This saved workflow does not confirm the current limit. Restore will verify the original value or report an error.'
        $view.Tone='Warning'
    }
    if($Guide -and $Guide.Verdict){
        $v=$Guide.Verdict
        $view.ResultTitle=[string]$v.Title
        $view.Recommendation=[string]$v.Recommendation
        $view.BeforeScore=Format-PCGuideNumber $v.BeforeMedian
        $view.AfterScore=Format-PCGuideNumber $v.AfterMedian
        $value=Format-PCGuideNumber $v.PercentChange '+0.00;-0.00;0.00'
        $view.Change=if($value -eq '--'){'--'}else{"$value%"}
        $view.Detail=[string]$v.Detail
        if($phase -ne 'Decision'){
            $view.RecommendationLabel='RECORDED TEST RECOMMENDATION'
            $view.Recommendation+=' This is the earlier test recommendation; the saved action is shown above.'
        }
    }
    if($LoadIssue){
        $view.Stage='Saved guided session could not be loaded';$view.Tone='Warning'
        $view.NextAction='Open Tuning to inspect any recovery record before starting another run.'
    }
    return $view
}
