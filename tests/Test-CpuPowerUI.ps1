$ErrorActionPreference='Stop'
function Assert($ok,$message){if(-not $ok){throw $message}}
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('PCInsight-CpuPowerUI-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dataDir|Out-Null
try{
    $ui=@{};foreach($n in 'CpuPowerDetect','CpuPowerInfo','CpuPL1','CpuPL2','CpuPowerApply','CpuPowerRestore','CpuPowerStatus','Status'){
        $c=[pscustomobject]@{IsEnabled=$false;Text='';Click=$null};$c|Add-Member ScriptMethod Add_Click {param($handler);$this.Click=$handler};$ui[$n]=$c
    }
    $script:job=$null;$script:updateJob=$null;$script:clockActionBusy=$false;$script:guide=$null;$script:clockGuideLocked=$false;$script:isAdministrator=$true
    $script:allow=$false;$script:confirmHook=$null;$script:confirmCount=0;$script:confirmText='';$script:confirmWasLocked=$false
    $script:probeCount=0;$script:writeCount=0;$script:restoreCount=0;$script:journalReadCount=0;$script:detectError='';$script:writeError='';$script:restoreError='';$script:lastError=''
    $script:hardware=[pscustomobject]@{Name='13th Gen Intel(R) Core(TM) i7-13700K';Identity='cpu-board';ProcessorId='BFEBFBFF000B0671';BIOS='4505';BootId='this-boot';RawLimitHex='000080FD0000807D';RawUnitsHex='0000000000000000';Supported=$true;Reason='';PL1Watts=125.0;PL2Watts=253.0;Locked=$false;PL1Enabled=$true;PL2Enabled=$true}
    function Test-PCClockGuideLocked {$script:clockGuideLocked}
    function Set-Busy($busy){Refresh-PCCpuPowerUI}
    function Confirm($message){
        $script:confirmCount++;$script:confirmText=$message
        $script:confirmWasLocked=$script:cpuPowerBusy -and -not $ui.CpuPowerDetect.IsEnabled -and -not $ui.CpuPowerApply.IsEnabled -and -not $ui.CpuPowerRestore.IsEnabled
        if($script:confirmHook){& $script:confirmHook}
        $script:allow
    }
    function Show-Error($message){$script:lastError=$message}
    function Get-PCCpuPowerHardware {
        $script:probeCount++
        if($script:detectError){throw $script:detectError}
        $script:hardware.PSObject.Copy()
    }
    function Read-PCCpuPowerJournal($path){$script:journalReadCount++;[pscustomobject]@{Name='i7-13700K';OriginalRawHex='000080FD0000807D';RawUnitsHex='0000000000000000'}}
    function Get-PCCpuPowerFields($raw){[pscustomobject]@{PL1Raw=125;PL2Raw=253}}
    function Get-PCCpuPowerUnit($raw){1.0}
    function Set-PCCpuPowerLimits($selected,$pl1,$pl2,$path){
        Assert ($script:cpuPowerBusy -and -not $ui.CpuPowerDetect.IsEnabled) 'Apply transaction was not protected by the UI lock'
        $script:writeCount++;$script:lastSelected=$selected;$script:lastPL1=$pl1;$script:lastPL2=$pl2
        if($script:writeError){throw $script:writeError}
        Set-Content -LiteralPath $path -Value 'saved-originals'
        'Applied and verified requested limits. Closing the app does not restore them.'
    }
    function Restore-PCCpuPowerLimits($path){
        Assert ($script:cpuPowerBusy -and -not $ui.CpuPowerDetect.IsEnabled) 'Restore transaction was not protected by the UI lock'
        $script:restoreCount++
        if($script:restoreError){throw $script:restoreError}
        Remove-Item -LiteralPath $path
        'Saved CPU power limits restored and read back.'
    }
    Set-Content -LiteralPath (Join-Path $dataDir 'cpu-power-restore.json') -Value 'saved-originals'
    . "$PSScriptRoot/../CpuPowerUI.ps1"
    Assert ($script:probeCount -eq 0 -and $script:writeCount -eq 0 -and $script:restoreCount -eq 0 -and $script:journalReadCount -eq 0) 'Startup accessed hardware or attempted recovery'
    Assert ($ui.CpuPowerRestore.IsEnabled -and $ui.CpuPowerStatus.Text -match 'record found' -and -not $ui.CpuPowerApply.IsEnabled) 'Startup did not disclose saved recovery or allowed an unprobed write'
    1..10|ForEach-Object{Refresh-PCCpuPowerUI}
    Assert ($script:probeCount -eq 0 -and $script:journalReadCount -eq 0) 'Refresh performed repeated hardware or journal reads'
    & $ui.CpuPowerApply.Click;Assert ($script:confirmCount -eq 0 -and $script:writeCount -eq 0) 'Apply bypassed manual detection'
    & $ui.CpuPowerRestore.Click
    Assert ($script:restoreCount -eq 0 -and $script:confirmWasLocked -and $script:confirmText -match 'Sustained PL1: 125 W' -and $ui.CpuPowerRestore.IsEnabled -and -not $script:cpuPowerBusy) 'Cancelled restore wrote settings or failed to display saved values / unlock'

    & $ui.CpuPowerDetect.Click
    Assert ($script:probeCount -eq 1 -and $ui.CpuPowerApply.IsEnabled -and $ui.CpuPL1.Text -eq '125' -and $ui.CpuPL2.Text -eq '253') 'Detection did not fill the supported live limits'
    Assert ($ui.CpuPowerInfo.Text -match '4505' -and $ui.CpuPowerInfo.Text -match 'Detected sustained PL1') 'Detection report lost provenance'
    $script:allow=$true
    foreach($invalid in '','24','254','125.5','1e2','NaN','1000','-25','+25','1,25'){
        $before=$script:confirmCount;$ui.CpuPL1.Text=$invalid;& $ui.CpuPowerApply.Click
        Assert ($script:writeCount -eq 0 -and $script:confirmCount -eq $before -and $script:lastError -match 'whole watts') "Invalid watts accepted: $invalid"
    }
    $ui.CpuPL1.Text='126';$ui.CpuPL2.Text='200';& $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 0 -and $script:lastError -match 'only reduces') 'PL1 increase was accepted'
    $ui.CpuPL1.Text='100';$ui.CpuPL2.Text='99';& $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 0 -and $script:lastError -match 'less than or equal') 'PL1 above PL2 was accepted'
    $ui.CpuPL1.Text='100';$ui.CpuPL2.Text='200';$script:allow=$false;& $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 0 -and $script:confirmWasLocked -and $script:confirmText -match 'does not restore' -and $ui.CpuPowerApply.IsEnabled -and -not $script:cpuPowerBusy) 'Cancelled apply changed settings or left the controls locked'

    # Every task or workflow lock blocks both stale programmatic clicks and visible controls.
    foreach($kind in 'job','update','clock','clockGuide','powerGuide','cpu'){
        switch($kind){'job'{$script:job='task'}'update'{$script:updateJob='update'}'clock'{$script:clockActionBusy=$true}'clockGuide'{$script:clockGuideLocked=$true}'powerGuide'{$script:guide=[pscustomobject]@{Phase='Review'}}'cpu'{$script:cpuPowerBusy=$true}}
        Refresh-PCCpuPowerUI;$before=$script:probeCount;$confirmBefore=$script:confirmCount
        & $ui.CpuPowerDetect.Click;& $ui.CpuPowerApply.Click;& $ui.CpuPowerRestore.Click
        Assert (-not $ui.CpuPowerDetect.IsEnabled -and -not $ui.CpuPowerApply.IsEnabled -and -not $ui.CpuPowerRestore.IsEnabled -and $script:probeCount -eq $before -and $script:confirmCount -eq $confirmBefore) "CPU action bypassed $kind lock"
        $script:job=$null;$script:updateJob=$null;$script:clockActionBusy=$false;$script:clockGuideLocked=$false;$script:guide=$null;$script:cpuPowerBusy=$false
    }
    $script:isAdministrator=$false;Refresh-PCCpuPowerUI
    Assert ($ui.CpuPowerDetect.IsEnabled -and -not $ui.CpuPowerApply.IsEnabled -and -not $ui.CpuPowerRestore.IsEnabled) 'Administrator gate failed'
    $script:isAdministrator=$true;Refresh-PCCpuPowerUI

    # Recheck locks after the modal confirmation; nothing is dispatched if another task appeared.
    $script:allow=$true;$script:confirmHook={$script:updateJob='late-update'}
    & $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 0 -and -not $ui.CpuPowerApply.IsEnabled -and $ui.CpuPowerStatus.Text -match 'Another task') 'Apply ignored a lock acquired during review'
    $script:updateJob=$null;$script:confirmHook=$null;Refresh-PCCpuPowerUI
    & $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 1 -and $script:lastPL1 -eq 100 -and $script:lastPL2 -eq 200 -and $script:lastSelected.BootId -eq 'this-boot') 'Apply lost reviewed values or hardware snapshot'
    Assert ($null -eq $script:cpuPowerSelected -and -not $ui.CpuPowerApply.IsEnabled -and $ui.CpuPowerRestore.IsEnabled -and -not $script:cpuPowerBusy -and $script:probeCount -eq 1) 'Apply did not invalidate old limits or secretly reprobed hardware'

    & $ui.CpuPowerDetect.Click;$script:writeError='Settings changed after detection. Detect again.'
    & $ui.CpuPowerApply.Click
    Assert ($script:writeCount -eq 2 -and $script:lastError -match 'changed after detection' -and $null -eq $script:cpuPowerSelected -and -not $script:cpuPowerBusy -and $ui.CpuPowerRestore.IsEnabled) 'Stale-state error was hidden or left old settings available'
    $script:writeError='';$script:detectError='PawnIO is not installed.'
    & $ui.CpuPowerDetect.Click
    Assert ($ui.CpuPowerInfo.Text -match 'PawnIO is not installed' -and -not $ui.CpuPowerApply.IsEnabled -and $ui.CpuPowerRestore.IsEnabled -and -not $script:cpuPowerBusy) 'Missing driver failure retained stale support or blocked recovery'
    $script:detectError='';$script:hardware.Supported=$false;$script:hardware.Reason='Firmware locks this register.'
    & $ui.CpuPowerDetect.Click
    Assert ($ui.CpuPowerInfo.Text -eq 'Firmware locks this register.' -and -not $ui.CpuPowerApply.IsEnabled) 'Unsupported hardware was treated as writable'
    $script:hardware.Supported=$true;$script:hardware.PL1Watts=20
    & $ui.CpuPowerDetect.Click
    Assert (-not $ui.CpuPowerApply.IsEnabled -and $ui.CpuPowerInfo.Text -match 'at least 25') 'Low current limit enabled an increase to the input minimum'
    $script:hardware.PL1Watts=500;$script:hardware.PL2Watts=1000
    & $ui.CpuPowerDetect.Click
    Assert ($ui.CpuPL1.Text -eq '253' -and $ui.CpuPL2.Text -eq '253') 'High firmware defaults escaped conservative UI cap'

    # Recovery remains available without a successful detection or any temperature reading.
    Clear-PCCpuPowerSelection 'No temperature or live support reading';Refresh-PCCpuPowerUI
    $script:restoreError='Saved record belongs to another Windows boot.'
    & $ui.CpuPowerRestore.Click
    Assert ($script:restoreCount -eq 1 -and $script:lastError -match 'another Windows boot' -and $ui.CpuPowerRestore.IsEnabled -and -not $script:cpuPowerBusy -and (Test-Path $script:cpuPowerJournalPath)) 'Failed restore lost its record or hid the boot gate'
    $script:restoreError='';$before=$script:probeCount
    & $ui.CpuPowerRestore.Click
    Assert ($script:restoreCount -eq 2 -and -not $ui.CpuPowerRestore.IsEnabled -and -not $ui.CpuPowerApply.IsEnabled -and $script:probeCount -eq $before -and -not (Test-Path $script:cpuPowerJournalPath)) 'Restore failed without temperatures or did not refresh recovery state'
    'PASS: CPU power UI startup, explicit detection, conservative whole-watt inputs, modal review, all task locks, stale settings, missing driver, boot recovery errors and temperature-independent restoration'
}finally{Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue}
