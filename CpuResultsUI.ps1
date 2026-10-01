. "$PSScriptRoot\CpuResults.ps1"
$script:cpuResultsRefreshing=$false
$script:cpuBatchComparison=$null
function Show-PCCpuBatchComparison {
    if($script:cpuResultsRefreshing){return}
    $before=$ui.CpuBatchBefore.SelectedItem;$after=$ui.CpuBatchAfter.SelectedItem
    $ui.CpuBatchBeforeText.Text=Format-PCCpuResultBatch $before
    $ui.CpuBatchAfterText.Text=Format-PCCpuResultBatch $after
    $script:cpuBatchComparison=Get-PCCpuBatchComparison $before $after
    $ui.CpuBatchExport.IsEnabled=$null -ne $script:cpuBatchComparison
    $ui.CpuBatchVerdict.Text=if($script:cpuBatchComparison){$script:cpuBatchComparison.Status+"`n`n"+($script:cpuBatchComparison.Notes -join "`n")}else{'Complete two CPU batches, then choose a reference A and a result B. Existing measurements remain saved when a new batch is cancelled.'}
}
function Refresh-PCCpuResultsUI {
    $beforeId=$ui.CpuBatchBefore.SelectedItem.BatchId;$afterId=$ui.CpuBatchAfter.SelectedItem.BatchId
    $batches=@(Get-PCCpuResultBatches $script:history | Sort-Object Timestamp -Descending)
    $script:cpuResultsRefreshing=$true
    try{
        $ui.CpuBatchBefore.ItemsSource=$batches;$ui.CpuBatchAfter.ItemsSource=$batches
        $a=@($batches | Where-Object {$_.BatchId -eq $beforeId})
        $b=@($batches | Where-Object {$_.BatchId -eq $afterId})
        $ui.CpuBatchAfter.SelectedItem=if($b.Count){$b[0]}elseif($batches.Count){$batches[0]}else{$null}
        $ui.CpuBatchBefore.SelectedItem=if($a.Count){$a[0]}elseif($batches.Count -gt 1){$batches[1]}else{$null}
    }finally{$script:cpuResultsRefreshing=$false}
    Show-PCCpuBatchComparison
}
function Select-PCCpuBatchExportPath {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON comparison (*.json)|*.json';$dialog.FileName='PC-Insight-CPU-comparison.json'
    if($dialog.ShowDialog($window)){$dialog.FileName}
}
$ui.CpuBatchBefore.Add_SelectionChanged({Show-PCCpuBatchComparison})
$ui.CpuBatchAfter.Add_SelectionChanged({Show-PCCpuBatchComparison})
$ui.CpuBatchRefresh.Add_Click({Refresh-PCCpuResultsUI})
$ui.CpuBatchExport.Add_Click({
    if(-not $script:cpuBatchComparison){return}
    try{
        $snapshot=$script:cpuBatchComparison | ConvertTo-Json -Depth 16 | ConvertFrom-Json
        $path=Select-PCCpuBatchExportPath
        if($path){Save-JsonAtomic $snapshot $path;$ui.Status.Text='CPU batch comparison saved.'}
    }catch{Show-Error $_.Exception.Message}
})
Refresh-PCCpuResultsUI
