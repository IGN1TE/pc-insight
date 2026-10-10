$script:endurancePath=Join-Path $dataDir 'gpu-endurance-status.json'
function Save-PCGpuEnduranceStatus([string]$State,[string]$Message){
    Save-JsonAtomic ([pscustomobject]@{State=$State;Message=$Message;Timestamp=(Get-Date).ToString('o')}) $script:endurancePath
    $ui.EnduranceStatus.Text=$Message
}
function Refresh-PCGpuEnduranceUI {
    $locked=$script:job -or $script:updateJob -or $script:clockActionBusy -or $script:cpuPowerBusy -or (Test-PCClockGuideLocked) -or ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))
    foreach($n in 'Endurance5','Endurance10'){$ui[$n].IsEnabled=-not $locked -and $null -ne $script:snapshot}
    $ui.EnduranceStop.IsEnabled=$script:job -and $script:jobKind -like 'endurance*'
}
function Start-PCGpuEnduranceUI([ValidateSet(5,10)][int]$Minutes){
    Refresh-PCGpuEnduranceUI
    if(-not $ui['Endurance'+$Minutes].IsEnabled){return}
    if(-not(Confirm "Run $Minutes minutes of continuous GPU shader load plus warm-up? Save work and close games. This tests the current settings and makes no clock changes. Stop saves a partial result. It does not automatically restore saved offsets or prove stability.")){return}
    try{
        $script:testPlan=Get-ActivePlan
        Save-PCGpuEnduranceStatus 'Running' "Starting $Minutes-minute GPU endurance test."
        Start-Task ('endurance'+$Minutes)
        if(-not $script:job){Save-PCGpuEnduranceStatus 'Interrupted' 'GPU endurance worker did not start.'}
    }catch{Save-PCGpuEnduranceStatus 'Interrupted' $_.Exception.Message;Show-Error $_.Exception.Message}
}
$ui.Endurance5.Add_Click({Start-PCGpuEnduranceUI 5})
$ui.Endurance10.Add_Click({Start-PCGpuEnduranceUI 10})
$ui.EnduranceStop.Add_Click({Cancel-Task})
if(Test-Path $script:endurancePath){
    try{
        $saved=Get-Content $script:endurancePath -Raw -Encoding UTF8|ConvertFrom-Json
        if($saved.State -in @('Running','Stopping')){Save-PCGpuEnduranceStatus 'Interrupted' 'Previous endurance test was interrupted. No completed result is claimed. Check Tuning for saved clock offsets; no settings were changed at startup.'}
        else{$ui.EnduranceStatus.Text=$saved.Message}
    }catch{$ui.EnduranceStatus.Text='Previous endurance status could not be read. No completed result is claimed.'}
}
Refresh-PCGpuEnduranceUI
