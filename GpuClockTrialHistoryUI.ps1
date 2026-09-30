# Browsing/exporting saved experiments is read-only. Loading inputs never applies.
$script:clockTrialCatalog=@();$script:clockTrialHistoryRefreshing=$false;$script:clockTrialComparison=$null
function Update-PCClockTrialHistoryControls([bool]$Busy=$false) {
    $entry=$ui.ClockTrialHistory.SelectedItem;$selected=$ui.ClockGPU.SelectedItem
    $ui.ExportSavedClockTrial.IsEnabled=$null -ne $entry
    $ui.ExportClockTrialComparison.IsEnabled=$null -ne $entry -and $null -ne $ui.ClockTrialReference.SelectedItem
    $canLoad=$false
    if($entry -and $selected -and -not $Busy -and -not (Test-PCClockUiBusy) -and -not (Test-Path -LiteralPath $script:clockJournalPath)){
        try{$null=Get-PCSavedClockTrialOffsets $entry.Report $selected;$canLoad=$true}catch{}
    }
    $ui.LoadClockTrialOffsets.IsEnabled=$canLoad
}
function Show-PCClockTrialHistoryComparison {
    if($script:clockTrialHistoryRefreshing){return}
    $a=$ui.ClockTrialReference.SelectedItem;$b=$ui.ClockTrialHistory.SelectedItem
    $script:clockTrialComparison=Compare-PCClockTrials $a.Report $b.Report
    $ui.ClockTrialComparisonResult.Text=Format-PCClockTrialComparison $script:clockTrialComparison $a.Report $b.Report
    Update-PCClockTrialHistoryControls
}
function Show-PCClockTrialHistorySelection {
    if($script:clockTrialHistoryRefreshing){return}
    $b=$ui.ClockTrialHistory.SelectedItem;$aId=$ui.ClockTrialReference.SelectedItem.Id
    $script:clockTrialHistoryRefreshing=$true
    try{
        $references=@($script:clockTrialCatalog|Where-Object Id -ne $b.Id)
        $ui.ClockTrialReference.ItemsSource=$references
        $a=@($references|Where-Object Id -eq $aId)
        if($a.Count){$ui.ClockTrialReference.SelectedItem=$a[0]}elseif($references.Count){$ui.ClockTrialReference.SelectedIndex=0}
        $ui.ClockTrialSavedResult.Text=if($b){'Saved experiment; not a current hardware check.'+"`n"+(Format-PCClockTrialReport $b.Report)}else{'No saved trial selected.'}
    }finally{$script:clockTrialHistoryRefreshing=$false}
    Show-PCClockTrialHistoryComparison
    if(Get-Command Show-PCClockTrialTelemetry -ErrorAction SilentlyContinue){Show-PCClockTrialTelemetry}
}
function Refresh-PCClockTrialHistory([string]$SelectId) {
    $keep=$ui.ClockTrialHistory.SelectedItem.Id;if($SelectId){$keep=$SelectId}
    $notices=[Collections.Generic.List[string]]::new()
    try{Protect-PCPreviousClockTrial $script:clockTrialReportPath}catch{$notices.Add('Last report could not be archived: '+$_.Exception.Message)}
    $script:clockTrialHistoryRefreshing=$true
    try{
        $catalog=Get-PCClockTrialHistory (Get-PCClockTrialHistoryFolder $script:clockTrialReportPath)
        $script:clockTrialCatalog=@($catalog.Entries)
        foreach($issue in @($catalog.Issues)){$notices.Add($issue)}
        $ui.ClockTrialHistory.ItemsSource=$script:clockTrialCatalog
        $match=@($script:clockTrialCatalog|Where-Object Id -eq $keep)
        if($match.Count){$ui.ClockTrialHistory.SelectedItem=$match[0]}elseif($script:clockTrialCatalog.Count){$ui.ClockTrialHistory.SelectedIndex=0}
        $ui.ClockTrialHistoryStatus.Text="Showing $($script:clockTrialCatalog.Count) recent saved trials (up to 50). All archives remain on this PC."
        if($notices.Count){$ui.ClockTrialHistoryStatus.Text+="`n"+($notices -join "`n")}
    }catch{$ui.ClockTrialHistoryStatus.Text='Could not read trial history: '+$_.Exception.Message}
    finally{$script:clockTrialHistoryRefreshing=$false}
    Show-PCClockTrialHistorySelection
}
function Select-PCClockTrialExportPath([string]$Name) {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON report (*.json)|*.json';$dialog.FileName=$Name
    if($dialog.ShowDialog() -eq $true){$dialog.FileName}
}
function Export-PCSavedClockTrial($Value,[string]$Name) {
    # Freeze selection before the dialog pumps WPF events or a worker completes.
    $json=$Value|ConvertTo-Json -Depth 10
    $path=Select-PCClockTrialExportPath $Name
    if($path){[IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false));$ui.ClockTrialHistoryStatus.Text='Saved report exported.'}
}
$ui.ClockTrialHistory.Add_SelectionChanged({Show-PCClockTrialHistorySelection})
$ui.ClockTrialReference.Add_SelectionChanged({Show-PCClockTrialHistoryComparison})
$ui.LoadClockTrialOffsets.Add_Click({
    if((Test-PCClockUiBusy) -or (Test-Path -LiteralPath $script:clockJournalPath)){return}
    try{
        $entry=$ui.ClockTrialHistory.SelectedItem
        if(-not $entry -or -not $ui.ClockGPU.SelectedItem){throw 'Select a saved trial and detect its GPU first.'}
        $null=Get-PCSavedClockTrialOffsets $entry.Report $ui.ClockGPU.SelectedItem
        # Read fresh device/range information before staging old input values.
        Refresh-PCClockDevices
        $values=Get-PCSavedClockTrialOffsets $entry.Report $ui.ClockGPU.SelectedItem
        $ui.CoreOffset.Text=[string]$values.CoreMHz;$ui.MemoryOffset.Text=[string]$values.MemoryMHz
        $ui.ClockTrialHistoryStatus.Text='Offset inputs loaded only. No clocks changed. Review and run a new trial to test them again; saved results do not establish stability.'
    }catch{$ui.ClockTrialHistoryStatus.Text=$_.Exception.Message;Show-Error $_.Exception.Message}
    Update-PCClockTrialHistoryControls
})
$ui.ExportSavedClockTrial.Add_Click({
    $entry=$ui.ClockTrialHistory.SelectedItem;if(-not $entry){return}
    try{Export-PCSavedClockTrial $entry.Report 'PC-Insight-saved-GPU-trial.json'}catch{Show-Error $_.Exception.Message}
})
$ui.ExportClockTrialComparison.Add_Click({
    $a=$ui.ClockTrialReference.SelectedItem;$b=$ui.ClockTrialHistory.SelectedItem;if(-not $a -or -not $b){return}
    try{
        $value=[pscustomobject]@{Comparison=(Compare-PCClockTrials $a.Report $b.Report);Reference=$a.Report;Current=$b.Report}
        Export-PCSavedClockTrial $value 'PC-Insight-GPU-trial-comparison.json'
    }catch{Show-Error $_.Exception.Message}
})
Refresh-PCClockTrialHistory
