. "$PSScriptRoot\EnduranceResults.ps1"
$script:enduranceResultsRefreshing=$false
function Show-PCEnduranceResult {
    if($script:enduranceResultsRefreshing){return}
    $selected=$ui.EnduranceHistory.SelectedItem
    $ui.EnduranceHistoryDetails.Text=if($selected){Get-PCSessionSummary $selected.Session @()}else{'No saved GPU endurance sessions. Run a 5- or 10-minute test above. Stopped sessions are saved too; at most ten recent sensor sessions are retained across all test types.'}
    $ui.EnduranceHistoryExport.IsEnabled=$null -ne $selected
}
function Refresh-PCEnduranceResults {
    $key=$ui.EnduranceHistory.SelectedItem.Key
    $items=@(Get-PCEnduranceResults $script:sessions)
    $script:enduranceResultsRefreshing=$true
    try{
        $ui.EnduranceHistory.ItemsSource=$items
        $previous=@($items | Where-Object Key -eq $key)
        $ui.EnduranceHistory.SelectedItem=if($previous.Count){$previous[0]}elseif($items.Count){$items[0]}else{$null}
    }finally{$script:enduranceResultsRefreshing=$false}
    Show-PCEnduranceResult
}
function Select-PCEnduranceExportPath {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON session (*.json)|*.json';$dialog.FileName='PC-Insight-GPU-endurance.json'
    if($dialog.ShowDialog($window)){$dialog.FileName}
}
$ui.EnduranceHistory.Add_SelectionChanged({Show-PCEnduranceResult})
$ui.EnduranceHistoryRefresh.Add_Click({Refresh-PCEnduranceResults})
$ui.EnduranceHistoryExport.Add_Click({
    if(-not $ui.EnduranceHistory.SelectedItem){return}
    try{
        $snapshot=$ui.EnduranceHistory.SelectedItem.Session | ConvertTo-Json -Depth 24 | ConvertFrom-Json
        $path=Select-PCEnduranceExportPath
        if($path){Save-JsonAtomic $snapshot $path;$ui.Status.Text='Saved GPU endurance session with retained readings and event evidence.'}
    }catch{Show-Error $_.Exception.Message}
})
Refresh-PCEnduranceResults
