# Bind once after controls exist. Selection details are rendered by the main window.
$script:sessionBrowserRefreshing=$false
$script:sessionAnnotationKey=''
function Refresh-PCSessionBrowser {
    $key=Get-PCSessionKey $ui.SessionPicker.SelectedItem.Session
    $category=if($ui.SessionFilter.SelectedItem){[string]$ui.SessionFilter.SelectedItem}else{'All'}
    $items=@(Get-PCSessionLibraryItems $script:sessions $category $ui.SessionSearch.Text ($ui.SessionPinnedOnly.IsChecked -eq $true))
    $script:sessionBrowserRefreshing=$true
    try{
        $ui.SessionPicker.ItemsSource=$items
        $previous=@($items | Where-Object Key -eq $key)
        $ui.SessionPicker.SelectedItem=if($previous.Count){$previous[0]}elseif($items.Count){$items[0]}else{$null}
    }finally{$script:sessionBrowserRefreshing=$false}
    $pins=@($script:sessions | Where-Object {$_.Pinned -eq $true}).Count
    $ui.SessionLibraryStatus.Text=('{0} shown / {1} saved; {2}/20 pinned. Keeps 30 recent unpinned sessions plus pins. Export important results as a backup.' -f $items.Count,@($script:sessions).Count,$pins)
    if(-not $items.Count){$ui.SessionLibraryStatus.Text='No sessions match these filters. Clear search or choose All. '+$ui.SessionLibraryStatus.Text}
    if($script:sessionReadFailed){$ui.SessionLibraryStatus.Text='Saved history could not be read; original file preserved. New results stay in memory only: export them before closing.'}
    Show-PCSessionAnnotation
}
function Show-PCSessionAnnotation {
    if($script:sessionBrowserRefreshing){return}
    $session=$ui.SessionPicker.SelectedItem.Session
    $key=Get-PCSessionKey $session
    # Background completions refresh the picker; preserve an in-progress note on the same result.
    if($key -ne $script:sessionAnnotationKey -or -not $session){
        $ui.SessionNote.Text=if($session){[string]$session.Note}else{''}
        $script:sessionAnnotationKey=$key
    }
    $ui.SessionPin.Content=if($session.Pinned -eq $true){'Unpin result'}else{'Pin result'}
    $ui.SessionPin.IsEnabled=$null -ne $session -and -not $script:sessionReadFailed
    $ui.SessionNote.IsEnabled=$null -ne $session -and -not $script:sessionReadFailed
    $ui.SessionSaveNote.IsEnabled=$null -ne $session -and -not $script:sessionReadFailed
}
function Save-PCSelectedSessionAnnotation([bool]$TogglePin=$false) {
    $session=$ui.SessionPicker.SelectedItem.Session
    if(-not $session){return}
    try{
        $pin=$session.Pinned -eq $true
        if($TogglePin){$pin=-not $pin}
        $updated=@(Set-PCSessionAnnotation $script:sessions (Get-PCSessionKey $session) $pin $ui.SessionNote.Text)
        # Persist before changing memory; a failed write leaves selection and old annotations intact.
        Save-PCSessionLibrary $updated (Join-Path $script:dataDir 'sessions.json') ([bool]$script:sessionReadFailed)
        $script:sessions=$updated
        $script:sessionAnnotationKey=''
        Refresh-SessionPicker
        if(Get-Command Refresh-PCEnduranceResults -ErrorAction SilentlyContinue){Refresh-PCEnduranceResults}
        $ui.Status.Text=if($TogglePin -and $pin){'Pinned result. It will survive the rolling history limit.'}elseif($TogglePin){'Unpinned result. Future tests may remove it from rolling history; export a backup if needed.'}else{'Saved result note.'}
    }catch{Show-Error $_.Exception.Message}
}
$ui.SessionFilter.ItemsSource=@('All','CPU','GPU','RAM','Monitoring','Other')
$ui.SessionFilter.SelectedIndex=0
$ui.SessionFilter.Add_SelectionChanged({Refresh-SessionPicker})
$ui.SessionSearch.Add_TextChanged({Refresh-SessionPicker})
$ui.SessionPinnedOnly.Add_Checked({Refresh-SessionPicker})
$ui.SessionPinnedOnly.Add_Unchecked({Refresh-SessionPicker})
$ui.SessionClearFilters.Add_Click({$ui.SessionSearch.Text='';$ui.SessionFilter.SelectedIndex=0;$ui.SessionPinnedOnly.IsChecked=$false;Refresh-SessionPicker})
$ui.SessionPin.Add_Click({Save-PCSelectedSessionAnnotation $true})
$ui.SessionSaveNote.Add_Click({Save-PCSelectedSessionAnnotation $false})
