# Loaded after worker helpers, before ShowDialog.
$script:guidePath=Join-Path $dataDir 'guided-optimization.json'
$script:guide=$null
$script:guideRun=$null
$script:guideLoadIssue=$null
if(Test-Path -LiteralPath $script:guidePath){
    try {
        $script:guide=Read-PCGuide $script:guidePath
        $script:guide=Resume-PCGuideState $script:guide $script:gpuJournalPath
        Save-PCGuide $script:guide $script:guidePath
    }catch{$script:guideLoadIssue=$_.Exception.Message}
}
function Refresh-GuideUI {
    if(Get-Command Update-PCCpuControls -ErrorAction SilentlyContinue){Update-PCCpuControls}
    $busy=$null -ne $script:job -or $null -ne $script:updateJob -or $script:clockActionBusy
    $phase=if($script:guide){$script:guide.Phase}else{'Not started'}
    $locked=$phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired')
    foreach($name in 'GuideDetect','GuideBaseline','GuideApply','GuideRestore','GuideKeep','GuideStop','GuideExport'){$ui[$name].IsEnabled=$false}
    $ui.GuideDetect.IsEnabled=-not $busy -and -not $locked
    $ui.GuideBaseline.IsEnabled=-not $busy -and $phase -eq 'Ready' -and $null -ne $script:snapshot
    $ui.GuideApply.IsEnabled=-not $busy -and $phase -eq 'Review'
    $ui.GuideKeep.IsEnabled=-not $busy -and $phase -eq 'Decision'
    $ui.GuideRestore.IsEnabled=-not $busy -and $null -ne $script:guide -and $phase -in @('Decision','Kept','RecoveryRequired')
    $ui.GuideStop.IsEnabled=$null -ne $script:guideRun -or (-not $busy -and $phase -eq 'Review')
    $ui.GuideExport.IsEnabled=-not $busy -and $null -ne $script:guide
    if($locked){
        foreach($name in 'Scan','Benchmark','PlansRefresh','Apply','Restore','SensorStart','MultiBenchmark','DashboardTest','DashboardRecord','MonitorStart','LongCPU','MemoryTest','GPUTest','DetectTuning','ApplyGPU','RestoreGPU','SaveBaseline','CompareBaseline','RepeatCPU','RepeatRAM','RepeatGPU','SaveProfile','LoadProfile','ReopenAdmin','CheckUpdate','DownloadUpdate','InstallUpdate'){$ui[$name].IsEnabled=$false}
    }
    if($phase -eq 'RecoveryRequired' -and -not $busy){$ui.ReopenAdmin.IsEnabled=$true}
    $pending=Test-Path -LiteralPath $script:gpuJournalPath
    $view=Get-PCGuidePresentation $script:guide $pending $script:guideLoadIssue
    $ui.GuideStage.Text=$view.Stage
    $ui.GuideNextAction.Text=$view.NextAction
    $color=switch($view.Tone){'Success'{'#84DFC3'};'Warning'{'#FFB5A3'};'Attention'{'#FFD58A'};default{'#C6AEFF'}}
    $brush=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $ui.GuideStatusCard.BorderBrush=$brush
    $ui.GuideStage.Foreground=$brush
    $ui.GuideMessage.Text=if($script:guideLoadIssue){$script:guideLoadIssue}elseif($script:guide){$script:guide.Message}else{'Start with Scan PC, then check compatibility. Nothing is applied during detection or baseline tests.'}
    $ui.GuideDevice.Text=if($script:guide){"$($script:guide.Device.Name) | Original $($script:guide.Device.Current) W | Proposed $($script:guide.TargetWatts) W (90%)"}else{'NVIDIA power-limit reduction only. This guided flow does not change clocks or voltage; manual NVIDIA offsets are on Tuning.'}
    $ui.GuideKeep.Content=if($script:guide){$view.KeepLabel}else{'Keep current limit'}
    $ui.GuideRestore.Content=if($script:guide){$view.RestoreLabel}else{'Restore original'}
    $ui.GuideResultTitle.Text=$view.ResultTitle
    $ui.GuideRecommendationLabel.Text=$view.RecommendationLabel
    $ui.GuideRecommendation.Text=$view.Recommendation
    $ui.GuideBeforeScore.Text=$view.BeforeScore
    $ui.GuideAfterScore.Text=$view.AfterScore
    $ui.GuideChange.Text=$view.Change
    $ui.GuideVerdict.Text=$view.Detail
    $ui.GuideRecovery.Text=$view.Recovery
}
function Interrupt-GuideRun([string]$reason) {
    if(-not $script:guideRun){return}
    $script:guideRun=$null
    try{Stop-PCGuide $script:guide $script:gpuJournalPath $script:guidePath $reason}
    catch{$ui.GuideMessage.Text='Could not save workflow status. Inspect Tuning recovery before making changes.'}
    Set-Busy $false
}
function Complete-GuideRun($records) {
    if(-not $script:guideRun){return}
    $stage=$script:guideRun;$script:guideRun=$null
    try {
        $expected=if($stage -eq 'baseline'){$script:guide.Device.Current}else{$script:guide.TargetWatts}
        Assert-PCGuideBatch $script:guide $records $expected
        $null=Assert-PCGuideLiveState $script:guide $expected
        if($stage -eq 'baseline'){
            if((Get-PCGroupStats $records).SpreadPercent -gt 5){throw 'Baseline spread exceeds 5%. Close background workloads and start a fresh baseline.'}
            $script:guide.Before=@($records)
            $script:guide.Baseline=[pscustomobject]@{Schema=1;Created=(Get-Date).ToString('o');Benchmarks=@($records);Sessions=@($records)}
            $script:guide.Phase='Review'
            $script:guide.Message='Three baseline runs completed. Review the 90% power ceiling below. Applying will start the retest automatically.'
        }else{
            $script:guide.After=@($records)
            $script:guide.Verdict=Get-PCGuideVerdict $script:guide
            $script:guide.Phase='Decision'
            $script:guide.Message='Retest complete. Review the measured trade-off, then choose Keep or Restore original.'
        }
        Save-PCGuide $script:guide $script:guidePath
    }catch{
        if($stage -eq 'after'){$script:guide.Phase='RunningAfter'}
        Stop-PCGuide $script:guide $script:gpuJournalPath $script:guidePath $_.Exception.Message
    }
    Set-Busy $false
}
$ui.GuideDetect.Add_Click({
    try{
        if(Test-Path -LiteralPath (Join-Path $dataDir 'gpu-clock-restore.json')){throw 'Restore saved GPU clock offsets before starting guided power-limit optimization. Manual clock benchmarks remain available.'}
        if(-not $script:snapshot){throw 'Scan PC first to establish hardware details.'}
        Set-Busy $true
        $caps=Get-PCTuningCapabilities
        if($caps.Issue){throw $caps.Issue}
        $script:guide=New-PCGuide $caps.Devices (Get-ActivePlan) $script:gpuJournalPath
        $script:guideLoadIssue=$null
        Save-PCGuide $script:guide $script:guidePath
    }catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}
})
$ui.GuideBaseline.Add_Click({
    try{
        if(Test-Path -LiteralPath (Join-Path $dataDir 'gpu-clock-restore.json')){throw 'Restore saved GPU clock offsets before the guided baseline.'}
        if($script:guide.Phase -ne 'Ready'){return}
        if(-not(Confirm 'Run three monitored GPU shader tests at the current limit? Each has a 5-second warm-up and 30-second measurement, with 10-second cooldowns. Save other work and close competing GPU workloads. This creates GPU load; no settings change during the baseline.')){return}
        $null=Assert-PCGuideLiveState $script:guide $script:guide.Device.Current
        $script:guide.Phase='RunningBaseline';$script:guide.Message='Recording three baseline runs.'
        Save-PCGuide $script:guide $script:guidePath
        $script:guideRun='baseline';$script:testPlan=$script:guide.Plan
        Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Baseline worker could not start.'}
        Refresh-GuideUI
    }catch{
        $reason=$_.Exception.Message
        if($script:guideRun){Interrupt-GuideRun $reason}
        elseif($script:guide.Phase -eq 'RunningBaseline'){$script:guide.Phase='Interrupted';$script:guide.Message=$reason;try{Save-PCGuide $script:guide $script:guidePath}catch{};Set-Busy $false}
        Show-Error $reason
    }
})
$ui.GuideApply.Add_Click({
    try{
        $g=$script:guide
        if(-not $g -or $g.Phase -ne 'Review'){return}
        if(-not(Confirm "Apply a $($g.TargetWatts) W ceiling to $($g.Device.Name), UUID $($g.Device.UUID), from $($g.Device.Current) W and automatically run three GPU tests? Original settings are saved and read back. Cancelling or a failed retest attempts restoration. If the process or PC crashes, recovery may require Restore on the next launch. This does not change clocks or voltages.")){return}
        Set-Busy $true
        Apply-PCGuide $g $script:gpuJournalPath $script:baselinePath $script:guidePath
        $script:baseline=$g.Baseline
        $script:guideRun='after';$script:testPlan=$g.Plan
        Start-Task 'repeatgpu'
        if(-not $script:job){throw 'Retest worker could not start.'}
    }catch{
        if($script:guideRun){Interrupt-GuideRun $_.Exception.Message}
        Show-Error $_.Exception.Message
    }finally{if(-not $script:job){Set-Busy $false};Refresh-GuideUI}
})
$ui.GuideStop.Add_Click({
    if($script:guideRun){Cancel-Task}
    elseif($script:guide.Phase -eq 'Review'){
        Stop-PCGuide $script:guide $script:gpuJournalPath $script:guidePath 'Baseline review cancelled.'
        Set-Busy $false
    }
})
$ui.GuideRestore.Add_Click({
    try {
        if(-not(Confirm "Restore and verify the saved $($script:guide.Device.Current) W original limit?")){return}
        Set-Busy $true
        Restore-PCGuide $script:guide $script:gpuJournalPath $script:guidePath
    }catch{
        $script:guide.Phase='RecoveryRequired';$script:guide.Message=$_.Exception.Message
        try{Save-PCGuide $script:guide $script:guidePath}catch{}
        Show-Error $script:guide.Message
    }finally{Set-Busy $false}
})
$ui.GuideKeep.Add_Click({
    try{
        if($script:guide.Phase -ne 'Decision'){return}
        if(-not(Confirm "Keep the current $($script:guide.TargetWatts) W ceiling? This is your choice, not a stability guarantee. The original limit remains saved and Restore stays available. No startup reapplication will be configured.")){return}
        $null=Assert-PCGuideLiveState $script:guide $script:guide.TargetWatts
        $journal=Read-PCPowerJournal $script:gpuJournalPath
        if($journal.UUID -ne $script:guide.Device.UUID -or [math]::Abs($journal.OriginalWatts-$script:guide.Device.Current) -gt 0.5){throw 'Recovery record no longer matches. Inspect Tuning.'}
        $script:guide.Phase='Kept';$script:guide.Message='You chose to keep the verified ceiling. Original settings remain saved for restoration.'
        Save-PCGuide $script:guide $script:guidePath
    }catch{Show-Error $_.Exception.Message}finally{Set-Busy $false}
})
$ui.GuideExport.Add_Click({
    try{
        $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON guided report (*.json)|*.json';$dialog.FileName='PC-Insight-guided-optimization.json'
        if($dialog.ShowDialog() -eq $true){Save-JsonAtomic ([pscustomobject]@{AppVersion=$script:appVersion;GuidedOptimization=$script:guide}) $dialog.FileName}
    }catch{Show-Error $_.Exception.Message}
})
Refresh-GuideUI

if($script:guide -and $script:guide.Phase -in @('RecoveryRequired','Decision')){
    $ui.Navigation.SelectedItem=@($ui.Navigation.Items|Where-Object Header -eq 'Optimize my PC')[0]
}
