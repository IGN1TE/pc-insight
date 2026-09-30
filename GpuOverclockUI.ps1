# Manual P0 offsets; detection and startup never write GPU settings.
$script:clockJournalPath=Join-Path $dataDir 'gpu-clock-restore.json'
$script:clockActionBusy=$false
function Test-PCClockUiBusy {
    $script:clockActionBusy -or $script:job -or $script:updateJob -or ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))
}
function Update-PCClockControlState([bool]$Busy=$false) {
    $blocked=$Busy -or (Test-PCClockUiBusy)
    $selected=$ui.ClockGPU.SelectedItem
    $ui.DetectClocks.IsEnabled=-not $blocked
    $ui.ClockGPU.IsEnabled=-not $blocked
    $ui.ApplyClocks.IsEnabled=-not $blocked -and $script:isAdministrator -and $selected -and $selected.Available
    $ui.RestoreClocks.IsEnabled=-not $blocked -and $script:isAdministrator -and (Test-Path -LiteralPath $script:clockJournalPath)
    $ui.CoreOffset.IsEnabled=-not $blocked -and $selected -and $selected.Available
    $ui.MemoryOffset.IsEnabled=$ui.CoreOffset.IsEnabled
}
function Show-PCClockSelection {
    $selected=$ui.ClockGPU.SelectedItem
    $ui.ClockInfo.Text='Detect clock support to read the current offsets and permitted ranges.'
    $ui.CoreOffset.Text='';$ui.MemoryOffset.Text=''
    if($selected){
        if($selected.Available){
            $ui.CoreOffset.Text=[string]$selected.CoreMHz;$ui.MemoryOffset.Text=[string]$selected.MemoryMHz
            $temp=if($null -eq $selected.TemperatureC){'unavailable'}else{"$($selected.TemperatureC) C"}
            $ui.ClockInfo.Text="P0 graphics offset: $($selected.CoreMHz) MHz | range $($selected.CoreMin) to $($selected.CoreMax) MHz`nP0 memory offset: $($selected.MemoryMHz) MHz | range $($selected.MemoryMin) to $($selected.MemoryMax) MHz`nGPU temperature at detection: $temp | Driver $($selected.Driver)`nReadable offsets do not confirm write support or stability."
        }else{$ui.ClockInfo.Text=$selected.Issue}
    }
    Update-PCClockControlState
}
function Refresh-PCClockDevices {
    $uuid=if($ui.ClockGPU.SelectedItem){$ui.ClockGPU.SelectedItem.UUID}else{''}
    $ui.ClockGPU.ItemsSource=@();Show-PCClockSelection
    $devices=@(Get-PCClockDevices)
    $ui.ClockGPU.ItemsSource=$devices
    $match=@($devices|Where-Object UUID -eq $uuid)
    if($match.Count){$ui.ClockGPU.SelectedItem=$match[0]}elseif($devices.Count){$ui.ClockGPU.SelectedIndex=0}
    if(-not $devices.Count){$ui.ClockInfo.Text='No NVIDIA GPUs were reported. AMD and Intel clock control is not implemented.'}
}
$ui.ClockGPU.Add_SelectionChanged({Show-PCClockSelection})
$ui.DetectClocks.Add_Click({
    if(Test-PCClockUiBusy){return}
    try{$script:clockActionBusy=$true;Set-Busy $true;Refresh-PCClockDevices;$ui.ClockStatus.Text='Detection complete. No GPU settings changed.'}
    catch{$ui.ClockStatus.Text=$_.Exception.Message}
    finally{$script:clockActionBusy=$false;Set-Busy $false}
})
$ui.ApplyClocks.Add_Click({
    if(Test-PCClockUiBusy){return}
    try{
        $selected=$ui.ClockGPU.SelectedItem
        if(-not $selected -or -not $selected.Available){throw 'Detect clock support and choose an available GPU first.'}
        $core=ConvertTo-PCClockInteger $ui.CoreOffset.Text;$memory=ConvertTo-PCClockInteger $ui.MemoryOffset.Text
        Assert-PCClockTargets $selected $core $memory
        $script:clockActionBusy=$true;Set-Busy $true
        if(-not (Confirm "Apply P0 clock offsets to $($selected.Name)?`nGPU: $($selected.UUID)`nCore: $($selected.CoreMHz) -> $core MHz`nMemory: $($selected.MemoryMHz) -> $memory MHz`n`nThese are absolute offset values, not increments. Close games and save your work first. Unstable clocks can cause artifacts, driver resets, crashes or lost work. Driver ranges are not safe-setting recommendations. Original offsets will be saved before writing. Closing PC Insight does not restore them. Use Restore saved clock offsets to undo this change.")){return}
        $ui.ClockStatus.Text=Set-PCGpuClockOffsets $selected $core $memory $script:clockJournalPath
        Refresh-PCClockDevices
    }catch{$ui.ClockStatus.Text=$_.Exception.Message;Show-Error $_.Exception.Message}
    finally{$script:clockActionBusy=$false;Set-Busy $false}
})
$ui.RestoreClocks.Add_Click({
    if(Test-PCClockUiBusy){return}
    try{
        $j=Read-PCClockJournal $script:clockJournalPath
        $script:clockActionBusy=$true;Set-Busy $true
        if(-not (Confirm "Restore saved offsets on $($j.Name), GPU $($j.UUID)?`nCore: $($j.OriginalCore) MHz; memory: $($j.OriginalMemory) MHz.`nThis restores the offsets present before PC Insight's first change, which may differ from factory settings.")){return}
        $ui.ClockStatus.Text=Restore-PCGpuClockOffsets $script:clockJournalPath
        Refresh-PCClockDevices
    }catch{$ui.ClockStatus.Text=$_.Exception.Message;Show-Error $_.Exception.Message}
    finally{$script:clockActionBusy=$false;Set-Busy $false}
})
if(Test-Path -LiteralPath $script:clockJournalPath){$ui.ClockStatus.Text='Saved clock recovery record found. No clock changes were made at startup. Use Restore saved clock offsets to recover the original values.'}
Update-PCClockControlState
