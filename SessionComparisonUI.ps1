# Loaded after main controls, before the saved-session pickers are populated.
$script:sessionComparison=$null
$script:comparisonReferenceSession=$null
$script:comparisonReferencesRefreshing=$false
function Test-PCSameComparisonSession($Left,$Right) {
    if(-not $Left -or -not $Right){return $false}
    [object]::ReferenceEquals($Left,$Right) -or ($Left.Timestamp -and $Left.Timestamp -eq $Right.Timestamp -and $Left.Test -eq $Right.Test)
}
function Refresh-PCComparisonReferences {
    $selected=$ui.SessionPicker.SelectedItem
    $script:comparisonReferencesRefreshing=$true
    try{
        $candidates=@($ui.SessionPicker.ItemsSource|Where-Object {
            $selected -and -not (Test-PCSameComparisonSession $_.Session $selected.Session)
        })
        $ui.CompareSessionPicker.ItemsSource=$candidates
        $preserved=@($candidates|Where-Object {Test-PCSameComparisonSession $_.Session $script:comparisonReferenceSession})
        if($preserved.Count){$ui.CompareSessionPicker.SelectedItem=$preserved[0]}
        elseif($candidates.Count){$ui.CompareSessionPicker.SelectedIndex=0}
    }finally{$script:comparisonReferencesRefreshing=$false}
    Show-PCSessionComparison
}
function Update-PCComparisonExportState {
    # Export only serializes saved data; live jobs do not invalidate this snapshot.
    $ui.ExportComparison.IsEnabled=$null -ne $script:sessionComparison
    if(-not $script:sessionComparison){$ui.ComparisonExportStatus.Text=$ui.ComparisonStatus.Text}
    else{$ui.ComparisonExportStatus.Text='Ready to export these two sessions.'}
    $ui.ExportComparison.ToolTip=$ui.ComparisonExportStatus.Text
}
function Show-PCSessionComparison {
    if($script:comparisonReferencesRefreshing){return}
    $script:sessionComparison=$null
    $ui.ComparisonRows.ItemsSource=@()
    $ui.ExportComparison.IsEnabled=$false
    $ui.ComparisonStatus.Text='Choose a reference session A. The session selected above is B.'
    $ui.ComparisonNotes.Text=''
    $ui.ComparisonExportStatus.Text=''
    $before=$ui.CompareSessionPicker.SelectedItem
    $after=$ui.SessionPicker.SelectedItem
    if(-not $before -or -not $after){
        if(-not $after){$ui.ComparisonStatus.Text='Choose a saved session at the top of this page.'}
        else{$ui.ComparisonStatus.Text='Save at least two different sessions to compare. Use Export this session to save the selected run alone.'}
        Update-PCComparisonExportState;return
    }
    if(Test-PCSameComparisonSession $before.Session $after.Session){
        $ui.ComparisonStatus.Text='Choose two different saved sessions.'
        Update-PCComparisonExportState;return
    }
    $script:comparisonReferenceSession=$before.Session
    try{
        $script:sessionComparison=Get-PCSessionComparison $before.Session $after.Session
        $ui.ComparisonRows.ItemsSource=$script:sessionComparison.Rows
        $ui.ComparisonStatus.Text=$script:sessionComparison.Status
        $ui.ComparisonNotes.Text=$script:sessionComparison.Notes -join "`n"
    }catch{
        $script:sessionComparison=$null
        $ui.ComparisonRows.ItemsSource=@()
        $ui.ComparisonStatus.Text='Could not compare these saved sessions: '+$_.Exception.Message
    }
    Update-PCComparisonExportState
}
$ui.CompareSessionPicker.Add_SelectionChanged({Show-PCSessionComparison})
function Select-PCComparisonExportPath {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Filter='JSON comparison (*.json)|*.json'
    $dialog.FileName='PC-Insight-comparison-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json'
    if($dialog.ShowDialog($window) -eq $true){$dialog.FileName}
}
$ui.ExportComparison.Add_Click({
    if(-not $script:sessionComparison){return}
    try{
        # WPF keeps dispatching while the dialog is open. A completed job may refresh the selectors.
        $snapshot=$script:sessionComparison|ConvertTo-Json -Depth 12|ConvertFrom-Json
        $path=Select-PCComparisonExportPath
        if(-not $path){return}
        Save-JsonAtomic $snapshot $path
        $ui.ComparisonExportStatus.Text='Saved comparison to '+$path
    }catch{Show-Error $_.Exception.Message}
})
