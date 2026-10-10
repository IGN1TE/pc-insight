# CPU power-limit writes are explicit; startup and UI refresh never probe or change hardware.
$script:cpuPowerJournalPath=Join-Path $dataDir 'cpu-power-restore.json'
$script:cpuPowerBusy=$false
$script:cpuPowerSelected=$null
function Test-PCCpuPowerOtherBusy {
    $clockGuideLocked=(Get-Command Test-PCClockGuideLocked -ErrorAction SilentlyContinue) -and (Test-PCClockGuideLocked)
    $script:job -or $script:updateJob -or $script:clockActionBusy -or $clockGuideLocked -or ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))
}
function Test-PCCpuPowerBusy {$script:cpuPowerBusy -or (Test-PCCpuPowerOtherBusy)}
function Test-PCCpuPowerSelection {
    $s=$script:cpuPowerSelected
    $null -ne $s -and $s.Supported -is [bool] -and $s.Supported -eq $true -and $s.Locked -is [bool] -and $s.Locked -eq $false -and $s.PL1Enabled -is [bool] -and $s.PL1Enabled -eq $true -and $s.PL2Enabled -is [bool] -and $s.PL2Enabled -eq $true -and $s.PL1Watts -ge 25 -and $s.PL2Watts -ge 25
}
function Refresh-PCCpuPowerUI {
    # This runs alongside ordinary UI refreshes. Hardware reads belong only to explicit actions.
    $locked=Test-PCCpuPowerBusy
    $available=Test-PCCpuPowerSelection
    $ui.CpuPowerDetect.IsEnabled=-not $locked
    $ui.CpuPL1.IsEnabled=-not $locked -and $available -and $script:isAdministrator
    $ui.CpuPL2.IsEnabled=$ui.CpuPL1.IsEnabled
    $ui.CpuPowerApply.IsEnabled=$ui.CpuPL1.IsEnabled
    $ui.CpuPowerRestore.IsEnabled=-not $locked -and $script:isAdministrator -and (Test-Path -LiteralPath $script:cpuPowerJournalPath)
}
function Clear-PCCpuPowerSelection([string]$Message) {
    $script:cpuPowerSelected=$null
    $ui.CpuPL1.Text='';$ui.CpuPL2.Text=''
    $ui.CpuPowerInfo.Text=$Message
}
function ConvertTo-PCCpuPowerUIWatts([string]$Text) {
    $value=0
    if($Text -notmatch '^\s*[0-9]{1,3}\s*$' -or -not [int]::TryParse($Text.Trim(),[ref]$value) -or $value -lt 25 -or $value -gt 253){throw 'Enter whole watts from 25 to 253 for each limit.'}
    return $value
}
function Show-PCCpuPowerDetection {
    Clear-PCCpuPowerSelection 'Reading CPU power-limit support...'
    $detected=Get-PCCpuPowerHardware
    if($null -eq $detected){throw 'CPU power-limit detection did not return a result.'}
    if($detected.Supported -ne $true){
        $reason=if($detected.Reason){[string]$detected.Reason}else{'This CPU, firmware or driver does not expose the supported power-limit control.'}
        $ui.CpuPowerInfo.Text=$reason
        return
    }
    $script:cpuPowerSelected=$detected
    if(-not (Test-PCCpuPowerSelection)){
        Clear-PCCpuPowerSelection 'CPU limits must both be enabled and unlocked, and each current limit must be at least 25 W. This preview cannot apply a change to the reported settings.'
        return
    }
    # A high firmware default never becomes a recommendation to increase power.
    $suggestedPL2=[math]::Floor([math]::Min(253,[double]$detected.PL2Watts))
    $suggestedPL1=[math]::Floor([math]::Min($suggestedPL2,[double]$detected.PL1Watts))
    $ui.CpuPL1.Text=[string]$suggestedPL1;$ui.CpuPL2.Text=[string]$suggestedPL2
    $ui.CpuPowerInfo.Text="$($detected.Name)`nDetected sustained PL1: $($detected.PL1Watts) W | burst PL2: $($detected.PL2Watts) W`nBIOS: $($detected.BIOS) | Both limits enabled and unlocked`nDetected at $((Get-Date).ToString('HH:mm:ss')). Values are checked again before a write."
    if(-not $script:isAdministrator){$ui.CpuPowerInfo.Text+="`nReopen as administrator to review or restore a change."}
}
$ui.CpuPowerDetect.Add_Click({
    if(Test-PCCpuPowerBusy){return}
    try{
        $script:cpuPowerBusy=$true;Set-Busy $true
        Show-PCCpuPowerDetection
        $ui.CpuPowerStatus.Text='Detection finished. No CPU settings changed.'
        if(Test-Path -LiteralPath $script:cpuPowerJournalPath){$ui.CpuPowerStatus.Text+=' Saved original limits are available for explicit restoration; closing PC Insight does not restore them.'}
    }catch{Clear-PCCpuPowerSelection $_.Exception.Message;$ui.CpuPowerStatus.Text='CPU power limits unavailable. No CPU settings changed.'}
    finally{$script:cpuPowerBusy=$false;Set-Busy $false;Refresh-PCCpuPowerUI}
})
$ui.CpuPowerApply.Add_Click({
    if(Test-PCCpuPowerBusy){return}
    $attempted=$false
    try{
        Refresh-PCCpuPowerUI
        if(-not $ui.CpuPowerApply.IsEnabled){return}
        $selected=$script:cpuPowerSelected
        $pl1=ConvertTo-PCCpuPowerUIWatts $ui.CpuPL1.Text;$pl2=ConvertTo-PCCpuPowerUIWatts $ui.CpuPL2.Text
        if($pl1 -gt $pl2){throw 'Sustained PL1 must be less than or equal to burst PL2.'}
        if($pl1 -gt $selected.PL1Watts -or $pl2 -gt $selected.PL2Watts){throw 'This preview only reduces or preserves each current limit. Restore saved limits before requesting a higher value.'}
        $script:cpuPowerBusy=$true;Set-Busy $true
        if(-not (Confirm "Apply CPU package power limits to $($selected.Name)?`nSustained PL1: $($selected.PL1Watts) -> $pl1 W`nBurst PL2: $($selected.PL2Watts) -> $pl2 W`n`nThese reductions can lower heat and performance. They do not change frequency or voltage directly. Original settings are saved before writing. Readback confirms the requested register values; firmware and other limits may override their effect. These are not instant hard wattage caps.`n`nClose demanding apps and save work first. Closing PC Insight does not restore this change. Use Restore saved CPU limits to return to the saved originals during this Windows boot. No automatic startup changes or reboot persistence are promised.")){return}
        if(Test-PCCpuPowerOtherBusy){$ui.CpuPowerStatus.Text='Another task became active. No CPU change was requested; finish that task and review again.';return}
        $attempted=$true
        $ui.CpuPowerStatus.Text=Set-PCCpuPowerLimits $selected $pl1 $pl2 $script:cpuPowerJournalPath
        if(Test-Path -LiteralPath $script:cpuPowerJournalPath){$ui.CpuPowerStatus.Text+=' Closing PC Insight does not restore this change. Use Restore saved CPU limits.'}
        $ui.Status.Text=$ui.CpuPowerStatus.Text
    }catch{$ui.CpuPowerStatus.Text=$_.Exception.Message;$ui.Status.Text=$ui.CpuPowerStatus.Text;Show-Error $_.Exception.Message}
    finally{
        if($attempted){Clear-PCCpuPowerSelection 'Detect CPU power limits again to read the current settings before another change.'}
        $script:cpuPowerBusy=$false;Set-Busy $false;Refresh-PCCpuPowerUI
    }
})
$ui.CpuPowerRestore.Add_Click({
    if(Test-PCCpuPowerBusy){return}
    $attempted=$false
    try{
        Refresh-PCCpuPowerUI
        if(-not $ui.CpuPowerRestore.IsEnabled){return}
        $journal=Read-PCCpuPowerJournal $script:cpuPowerJournalPath
        $original=Get-PCCpuPowerFields $journal.OriginalRawHex
        $unit=Get-PCCpuPowerUnit $journal.RawUnitsHex
        $originalPL1=$original.PL1Raw*$unit;$originalPL2=$original.PL2Raw*$unit
        $script:cpuPowerBusy=$true;Set-Busy $true
        if(-not (Confirm "Restore saved CPU power limits on $($journal.Name)?`nSustained PL1: $originalPL1 W`nBurst PL2: $originalPL2 W`n`nThese are the settings saved before PC Insight first changed them. They may differ from factory defaults and may use more power. Restoration requires matching CPU, firmware and Windows boot identity. Temperature readings are not required to restore. No benchmark will start.")){return}
        if(Test-PCCpuPowerOtherBusy){$ui.CpuPowerStatus.Text='Another task became active. Restoration was not requested; finish that task and review again.';return}
        $attempted=$true
        $ui.CpuPowerStatus.Text=Restore-PCCpuPowerLimits $script:cpuPowerJournalPath
        $ui.Status.Text=$ui.CpuPowerStatus.Text
    }catch{$ui.CpuPowerStatus.Text=$_.Exception.Message;$ui.Status.Text=$ui.CpuPowerStatus.Text;Show-Error $_.Exception.Message}
    finally{
        if($attempted){Clear-PCCpuPowerSelection 'Detect CPU power limits again to read the current settings.'}
        $script:cpuPowerBusy=$false;Set-Busy $false;Refresh-PCCpuPowerUI
    }
})
if(Test-Path -LiteralPath $script:cpuPowerJournalPath){$ui.CpuPowerStatus.Text='Saved CPU limit recovery record found. No settings changed at startup. Restore saved CPU limits checks the CPU, BIOS and Windows boot before recovery.'}
elseif(-not $script:isAdministrator){$ui.CpuPowerStatus.Text='No CPU settings changed. Reopen as administrator to review or restore CPU power limits.'}
Refresh-PCCpuPowerUI
