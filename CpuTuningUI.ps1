. "$PSScriptRoot\CpuTuning.ps1"
function Refresh-PCCpuTuningUI {
    $script:cpuReadiness=Get-PCCpuTuningReadiness $script:snapshot
    $ui.CpuReadinessText.Text=Format-PCCpuTuningReadiness $script:cpuReadiness
    $ui.CpuControlTable.ItemsSource=@($script:cpuReadiness.Controls)
    $locked=$script:job -or $script:updateJob -or $script:clockActionBusy -or $script:cpuPowerBusy -or (Test-PCClockGuideLocked) -or ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))
    $ui.CpuReadinessScan.IsEnabled=-not $locked
    $ui.CpuBaselineRun.IsEnabled=-not $locked -and $script:cpuReadiness.CanBenchmark
    $ui.CpuBaselineCancel.IsEnabled=$null -ne $script:job -and $script:jobKind -eq 'repeatcpu' -and -not $script:updateJob
    $ui.CpuReadinessExport.IsEnabled=$null -ne $script:snapshot
    $ui.CpuVendorHelp.IsEnabled=$null -ne $script:cpuReadiness.VendorRequirementsUrl
}
function Start-PCCpuReadinessBaseline {
    Refresh-PCCpuTuningUI
    if(-not $ui.CpuBaselineRun.IsEnabled){return}
    if(-not (Confirm 'Run three monitored 60-second CPU tests with cooldowns? Save work and close other demanding apps first. Temperature checks apply; Cancel discards this batch. No CPU settings change. Results describe this SHA-256 workload, not overall performance or stability.')){return}
    try{$script:testPlan=Get-ActivePlan;Start-Task 'repeatcpu';Refresh-PCCpuTuningUI}catch{Show-Error $_.Exception.Message}
}
function Select-PCCpuReadinessExportPath {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON report (*.json)|*.json';$dialog.FileName='PC-Insight-CPU-readiness.json'
    if($dialog.ShowDialog()){return $dialog.FileName};return $null
}
$ui.CpuReadinessScan.Add_Click({Refresh-PCCpuTuningUI;if($ui.CpuReadinessScan.IsEnabled){Start-Task 'scan'}})
$ui.CpuBaselineRun.Add_Click({Start-PCCpuReadinessBaseline})
$ui.CpuBaselineCancel.Add_Click({
    Refresh-PCCpuTuningUI
    if(-not $ui.CpuBaselineCancel.IsEnabled){return}
    try{Cancel-Task}catch{Show-Error $_.Exception.Message}finally{Refresh-PCCpuTuningUI}
})
$ui.CpuReadinessExport.Add_Click({
    try{
        Refresh-PCCpuTuningUI;if(-not $ui.CpuReadinessExport.IsEnabled){return}
        $report=$script:cpuReadiness;$path=Select-PCCpuReadinessExportPath
        if($path){Save-JsonAtomic $report $path;$ui.Status.Text='CPU readiness report saved. No CPU settings changed.'}
    }catch{Show-Error $_.Exception.Message}
})
$ui.CpuVendorHelp.Add_Click({
    Refresh-PCCpuTuningUI
    # URL comes only from the fixed vendor mapping in CpuTuning.ps1.
    if($script:cpuReadiness.VendorRequirementsUrl){try{Start-Process $script:cpuReadiness.VendorRequirementsUrl}catch{Show-Error $_.Exception.Message}}
})
Refresh-PCCpuTuningUI
