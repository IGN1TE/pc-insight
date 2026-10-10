function Get-PCEnduranceResults($Sessions){
    @($Sessions | Where-Object {$_.Test -like 'GPU-endurance-*'} | Sort-Object Timestamp -Descending | ForEach-Object {
        $state=if($_.Completed -eq $true -and -not $_.StopReason){'Completed'}else{'Stopped / incomplete'}
        if(@($_.ReliabilityEvidence.Events).Where({$null -ne $_}).Count){$state+='; events to review'}
        [pscustomobject]@{Key=([string]$_.Timestamp+'|'+[string]$_.Test);Label=('{0} | {1} min | {2}' -f $_.Timestamp,($_.RequestedSeconds/60),$state);Session=$_}
    })
}
