$script:clockGuide=$null;$script:clockGuideRun=$false;$script:clockGuideIssue=''
$script:clockGuidePath=Join-Path $dataDir 'guided-core-trial.json'
function Test-PCClockGuideLocked {$script:clockGuide -and $script:clockGuide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')}
function Refresh-PCClockGuideUI {
    $busy=$script:job -or $script:updateJob -or $script:clockActionBusy -or $script:cpuPowerBusy
    $phase=if($script:clockGuide){$script:clockGuide.Phase}else{''}
    $powerLocked=$script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')
    foreach($n in 'CoreTrialStart','CoreTrialApply','CoreTrialKeep','CoreTrialRestore','CoreTrialCancel'){$ui[$n].IsEnabled=$false}
    $ui.CoreTrialStart.IsEnabled=-not $busy -and -not $powerLocked -and -not (Test-PCClockGuideLocked) -and $script:snapshot -and $script:isAdministrator -and -not $script:clockGuideIssue
    $ui.CoreTrialApply.IsEnabled=-not $busy -and $phase -eq 'Review'
    $ui.CoreTrialKeep.IsEnabled=-not $busy -and $phase -eq 'Decision'
    $ui.CoreTrialRestore.IsEnabled=-not $busy -and $script:isAdministrator -and $phase -in @('Decision','Kept','RecoveryRequired')
    $ui.CoreTrialCancel.IsEnabled=$script:clockGuideRun -or (-not $busy -and $phase -eq 'Review')
    $ui.CoreTrialStatus.Text=if($script:clockGuideIssue){$script:clockGuideIssue}elseif($script:clockGuide){$phase+': '+$script:clockGuide.Summary}else{'Scan PC and detect clock support, then record a fresh baseline. No settings change during baseline.'}
    if(Test-PCClockGuideLocked){
        foreach($n in 'Scan','Benchmark','PlansRefresh','Apply','Restore','SensorStart','MultiBenchmark','DashboardTest','DashboardRecord','MonitorStart','LongCPU','MemoryTest','GPUTest','DetectTuning','ApplyGPU','RestoreGPU','SaveBaseline','CompareBaseline','RepeatCPU','RepeatRAM','RepeatGPU','SaveProfile','LoadProfile','ReopenAdmin','CheckUpdate','DownloadUpdate','InstallUpdate','GuideDetect','GuideBaseline','GuideApply','GuideRestore','GuideKeep','DetectClocks','ApplyClocks','RestoreClocks','ClockGPU','CoreOffset','MemoryOffset'){$ui[$n].IsEnabled=$false}
        if($phase -eq 'RecoveryRequired' -and -not $busy){$ui.ReopenAdmin.IsEnabled=$true;$ui.RestoreClocks.IsEnabled=$script:isAdministrator -and (Test-Path $script:clockJournalPath)}
    }
}
function Interrupt-PCClockGuide([string]$Reason){
    if(-not $script:clockGuideRun){return}
    $script:clockGuideRun=$false
    try{Stop-PCClockGuide $script:clockGuide $script:clockJournalPath $script:clockGuidePath $Reason}catch{$script:clockGuideIssue='Could not save trial status. Use Tuning to inspect and restore the saved clock offsets.'}
    Set-Busy $false
}
function Complete-PCClockGuideRun($Records){
    if(-not $script:clockGuideRun){return}
    $script:clockGuideRun=$false
    try{Complete-PCClockGuide $script:clockGuide $Records $script:clockJournalPath $script:clockGuidePath}catch{$ui.Status.Text=$_.Exception.Message}
    Set-Busy $false
}
$ui.CoreTrialStart.Add_Click({
    if($script:job -or $script:updateJob -or (Test-PCClockGuideLocked)){return}
    try{
        if(-not $script:snapshot){throw 'Scan PC first.'}
        if(Test-Path $script:gpuJournalPath){throw 'Restore the saved GPU power limit before a core trial.'}
        if($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')){throw 'Finish the guided power workflow first.'}
        $selected=$ui.ClockGPU.SelectedItem;if(-not $selected){throw 'Detect clock support and select your GPU first.'}
        $clocks=@(Get-PCClockDevices);if($clocks.Count -ne 1){throw 'Guided core trials currently require exactly one NVIDIA GPU to avoid ambiguous benchmark targeting.'}
        $clock=Get-PCClockDevice $selected.UUID;$power=Get-PCDeviceById $selected.UUID
        $g=New-PCClockGuide $clock $power (Get-ActivePlan) $script:clockJournalPath
        if(-not (Confirm 'Record three GPU shader baseline runs? This creates GPU load but does not change clocks. The later trial proposes only +15 MHz core; memory stays unchanged. Save work and close other GPU workloads.')){return}
        $script:clockGuide=$g;Save-PCClockGuide $g $script:clockGuidePath
        $script:clockGuideRun=$true;$script:testPlan=$g.Plan;Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Baseline worker did not start.'}
    }catch{if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message};Show-Error $_.Exception.Message}
    finally{Refresh-PCClockGuideUI}
})
$ui.CoreTrialApply.Add_Click({
    if($script:job -or $script:updateJob -or -not $script:clockGuide -or $script:clockGuide.Phase -ne 'Review'){return}
    try{
        $g=$script:clockGuide
        if(-not (Confirm "Apply core offset $($g.Clock.CoreMHz) -> $($g.TargetCore) MHz to $($g.Clock.Name), GPU $($g.Clock.UUID), and run three retests? Memory remains $($g.Clock.MemoryMHz) MHz. Unstable clocks can cause crashes or lost work. Cancel or a failed retest attempts restoration; a system crash may require restoration after relaunch. No voltage changes or stability guarantee.")){return}
        Set-Busy $true
        Apply-PCClockGuide $g $script:clockJournalPath $script:clockGuidePath
        $script:clockGuideRun=$true;$script:testPlan=$g.Plan;Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Retest worker did not start.'}
    }catch{if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message};Show-Error $_.Exception.Message}
    finally{if(-not $script:job){Set-Busy $false}}
})
$ui.CoreTrialCancel.Add_Click({if($script:clockGuideRun){Cancel-Task}else{Stop-PCClockGuide $script:clockGuide $script:clockJournalPath $script:clockGuidePath 'Trial review cancelled.';Set-Busy $false}})
$ui.CoreTrialRestore.Add_Click({
    try{if(-not (Confirm 'Restore and read back the original offsets saved for this core trial?')){return};Restore-PCClockGuide $script:clockGuide $script:clockJournalPath $script:clockGuidePath;$ui.Status.Text=$script:clockGuide.Summary}
    catch{$script:clockGuide.Phase='RecoveryRequired';$script:clockGuide.Summary=$_.Exception.Message;try{Save-PCClockGuide $script:clockGuide $script:clockGuidePath}catch{};Show-Error $_.Exception.Message}
    finally{Set-Busy $false}
})
$ui.CoreTrialKeep.Add_Click({try{if(Confirm 'Keep the verified trial offsets? This does not establish stability. Original values remain saved for explicit restoration.'){Keep-PCClockGuide $script:clockGuide $script:clockJournalPath $script:clockGuidePath}}catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}})
if(Test-Path $script:clockGuidePath){
    try{
        $script:clockGuide=Read-PCClockGuide $script:clockGuidePath
        if($script:clockGuide.Phase -in @('Applying','RunningAfter','Decision','RecoveryRequired')){$script:clockGuide.Phase='RecoveryRequired';$script:clockGuide.Summary='An unfinished trial was found. Restore saved offsets before another trial. No settings were changed at startup.'}
        elseif($script:clockGuide.Phase -in @('RunningBaseline','Review')){$script:clockGuide.Phase='Interrupted';$script:clockGuide.Summary='Previous baseline was interrupted or is stale; start a fresh trial.'}
        Save-PCClockGuide $script:clockGuide $script:clockGuidePath
    }catch{$script:clockGuideIssue='Saved trial could not be read. Use manual Restore saved clock offsets on Tuning. '+$_.Exception.Message}
}
Refresh-PCClockGuideUI
