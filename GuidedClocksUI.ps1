$script:clockGuide=$null;$script:clockGuideRun=$false;$script:clockGuideIssue=''
$script:clockGuidePath=Join-Path $dataDir 'guided-core-trial.json'
function Test-PCClockGuideLocked {$script:clockGuide -and $script:clockGuide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')}
function Refresh-PCClockGuideUI {
    $busy=$script:job -or $script:updateJob -or $script:clockActionBusy -or $script:cpuPowerBusy
    $phase=if($script:clockGuide){$script:clockGuide.Phase}else{''}
    $powerLocked=$script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')
    foreach($n in 'CoreTrialStart','CoreTrialApply','CoreTrialKeep','CoreTrialRestore','CoreTrialCancel','GpuScanStart','GpuScanApply'){$ui[$n].IsEnabled=$false}
    $ui.CoreTrialStart.IsEnabled=-not $busy -and -not $powerLocked -and -not (Test-PCClockGuideLocked) -and $script:snapshot -and $script:isAdministrator -and -not $script:clockGuideIssue
    $ui.GpuScanStart.IsEnabled=$ui.CoreTrialStart.IsEnabled
    $ui.GpuScanApply.IsEnabled=-not $busy -and -not $powerLocked -and $script:isAdministrator -and $phase -eq 'Restored' -and $script:clockGuide.ScanFinished -eq $true -and $null -ne $script:clockGuide.RecommendedCore -and -not $script:clockGuideIssue
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
    try{
        if($script:clockGuide.ScanMode){
            Complete-PCGpuAutoScanBatch $script:clockGuide $Records $script:clockJournalPath $script:clockGuidePath
            if($script:clockGuide.Phase -eq 'RunningAfter'){
                $script:clockGuideRun=$true;$script:testPlan=$script:clockGuide.Plan;Start-Task 'repeatgpu'
                if(-not $script:job){throw 'Next scan worker did not start.'}
            }
        }else{Complete-PCClockGuide $script:clockGuide $Records $script:clockJournalPath $script:clockGuidePath}
    }catch{if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message};$ui.Status.Text=$_.Exception.Message}
    Set-Busy ([bool]$script:job)
}
function Start-PCClockGuideBaseline([switch]$AutoScan){
    Refresh-PCClockGuideUI
    if(-not $ui.CoreTrialStart.IsEnabled){return}
    try{
        if(-not $script:snapshot){throw 'Scan PC first.'}
        if(Test-Path $script:gpuJournalPath){throw 'Restore the saved GPU power limit before a core trial.'}
        if($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')){throw 'Finish the guided power workflow first.'}
        $selected=$ui.ClockGPU.SelectedItem;if(-not $selected){throw 'Detect clock support and select your GPU first.'}
        $clocks=@(Get-PCClockDevices);if($clocks.Count -ne 1){throw 'Guided core trials currently require exactly one NVIDIA GPU to avoid ambiguous benchmark targeting.'}
        $clock=Get-PCClockDevice $selected.UUID;$power=Get-PCDeviceById $selected.UUID
        $g=New-PCClockGuide $clock $power (Get-ActivePlan) $script:clockJournalPath
        if($AutoScan){Enable-PCGpuAutoScan $g}
        $prompt=if($AutoScan){'Record three GPU baseline runs for an automatic core scan? Baseline does not change settings. After separate review, the scan tests +15, +30 and +45 MHz above the starting core offset, three runs each, then restores the starting offsets. Allow about 9 minutes total. Save work and close games and other tuning utilities.'}else{'Record three GPU shader baseline runs? This creates GPU load but does not change clocks. The later trial proposes only +15 MHz core; memory stays unchanged. Save work and close other GPU workloads.'}
        if(-not (Confirm $prompt)){return}
        Refresh-PCClockGuideUI;if(-not $ui.CoreTrialStart.IsEnabled){return}
        $script:clockGuide=$g;Save-PCClockGuide $g $script:clockGuidePath
        $script:clockGuideRun=$true;$script:testPlan=$g.Plan;Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Baseline worker did not start.'}
    }catch{if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message};Show-Error $_.Exception.Message}
    finally{Refresh-PCClockGuideUI}
}
$ui.CoreTrialStart.Add_Click({Start-PCClockGuideBaseline})
$ui.GpuScanStart.Add_Click({Start-PCClockGuideBaseline -AutoScan})
$ui.CoreTrialApply.Add_Click({
    Refresh-PCClockGuideUI;if(-not $ui.CoreTrialApply.IsEnabled){return}
    try{
        $g=$script:clockGuide
        $prompt=if($g.ScanMode){"Run the bounded automatic core scan on $($g.Clock.Name), GPU $($g.Clock.UUID)?`nStarting core offset: $($g.Clock.CoreMHz) MHz. Test offsets: $([int]$g.Clock.CoreMHz+15), $([int]$g.Clock.CoreMHz+30), $([int]$g.Clock.CoreMHz+45) MHz. Memory remains $($g.Clock.MemoryMHz) MHz.`n`nThis approval covers these three steps only. Each step runs three GPU tests. Finish, Cancel or test failure attempts restoration of the starting offsets. A system crash can prevent restoration; reopen and use Restore. Unstable clocks can cause artifacts, crashes or lost work. No maximum-overclock or stability guarantee. The recommendation is never applied automatically."}else{"Apply core offset $($g.Clock.CoreMHz) -> $($g.TargetCore) MHz to $($g.Clock.Name), GPU $($g.Clock.UUID), and run three retests? Memory remains $($g.Clock.MemoryMHz) MHz. Unstable clocks can cause crashes or lost work. Cancel or a failed retest attempts restoration; a system crash may require restoration after relaunch. No voltage changes or stability guarantee."}
        if(@($g.Before | ForEach-Object {$_.Frames} | Where-Object {$_.CPUWarning}).Count){$prompt+="`n`nCPU temperatures were unavailable in some or all baseline samples. GPU temperature checks remain active. CPU thermal protection cannot cover missing CPU readings."}
        if(-not (Confirm $prompt)){return}
        Refresh-PCClockGuideUI;if(-not $ui.CoreTrialApply.IsEnabled){return}
        Set-Busy $true
        Apply-PCClockGuide $g $script:clockJournalPath $script:clockGuidePath
        $script:clockGuideRun=$true;$script:testPlan=$g.Plan;Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Retest worker did not start.'}
    }catch{if($script:clockGuideRun){Interrupt-PCClockGuide $_.Exception.Message};Show-Error $_.Exception.Message}
    finally{if(-not $script:job){Set-Busy $false}}
})
$ui.GpuScanApply.Add_Click({
    Refresh-PCClockGuideUI;if(-not $ui.GpuScanApply.IsEnabled){return}
    try{
        $g=$script:clockGuide
        if(-not (Confirm "Apply the measured candidate on $($g.Clock.Name)? Core offset $($g.Clock.CoreMHz) -> $($g.RecommendedCore) MHz; memory $($g.Clock.MemoryMHz) MHz. This is based on a short shader test, not a stability certificate. Save work first. Originals will be saved again, with Keep/Restore available.")){return}
        Refresh-PCClockGuideUI;if(-not $ui.GpuScanApply.IsEnabled){return}
        $script:clockActionBusy=$true;Set-Busy $true
        Apply-PCGpuScanRecommendation $g $script:clockJournalPath $script:clockGuidePath
    }catch{Show-Error $_.Exception.Message}
    finally{$script:clockActionBusy=$false;Set-Busy $false}
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
