$ErrorActionPreference='Stop'
. "$PSScriptRoot/../CpuPower.ps1"
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('pc-cpu-power-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$script:journal=Join-Path $directory 'restore.json'
$script:diskSave=(Get-Command Save-PCCpuPowerJournal).ScriptBlock
$script:original=[pscustomobject]@{Name='13th Gen Intel(R) Core(TM) i7-13700K';Identity='GenuineIntel/6/B7/one-socket/board-test';ProcessorId='MOCK-BF';BIOS='4505';BootId='boot-1';RawLimitHex='00428B6000DD87D0';RawUnitsHex='00000000000A0E03';Supported=$true;Reason='';PL1Watts=250.0;PL2Watts=364.0;Locked=$false;PL1Enabled=$true;PL2Enabled=$true}
function Update-MockRaw([string]$Hex){
    $script:live.RawLimitHex=$Hex;$fields=Get-PCCpuPowerFields $Hex;$unit=Get-PCCpuPowerUnit $script:live.RawUnitsHex
    $script:live.PL1Watts=$fields.PL1Raw*$unit;$script:live.PL2Watts=$fields.PL2Raw*$unit
    $script:live.Locked=$fields.Locked;$script:live.PL1Enabled=$fields.PL1Enabled;$script:live.PL2Enabled=$fields.PL2Enabled
}
function Reset-Mock {
    $script:live=$script:original|Select-Object *;$script:admin=$true;$script:mode='normal';$script:reads=0;$script:saveCount=0
    $script:writes=[Collections.Generic.List[object]]::new()
    if(Test-Path -LiteralPath $script:journal){Remove-Item -LiteralPath $script:journal}
}
function Test-PCCpuPowerAdministrator {$script:admin}
function Save-PCCpuPowerJournal($Journal,[string]$JournalPath){
    $script:saveCount++
    if($script:mode -eq 'save-pending-fails' -or ($script:mode -eq 'save-applied-fails' -and $script:saveCount -eq 2)){throw 'Mock disk save failed'}
    & $script:diskSave $Journal $JournalPath
}
function Get-PCCpuPowerHardware {
    $script:reads++
    if($script:mode -eq 'missing-driver'){throw 'Installed PawnIO driver unavailable'}
    if($script:reads -eq 2){
        if($script:mode -eq 'prewrite-race'){Update-MockRaw (New-PCCpuPowerTargetHex $script:live 201 251)}
        if($script:mode -eq 'prewrite-lock'){Update-MockRaw ('8'+$script:live.RawLimitHex.Substring(1))}
    }
    if($script:mode -eq 'readback-unavailable' -and $script:writes.Count -gt 0){throw 'Hardware vanished after write'}
    $script:live|Select-Object *
}
function Set-PCCpuPowerHardware([string]$ExpectedRawHex,[string]$TargetRawHex){
    Assert (Test-Path -LiteralPath $script:journal) 'Hardware write preceded durable recovery journal'
    $j=Read-PCCpuPowerJournal $script:journal
    Assert ($j.OriginalRawHex -ceq $script:original.RawLimitHex) 'First originals were overwritten'
    Assert ($j.State -in @('Pending','Restoring','RecoveryRequired')) 'Write started without pending or restore journal'
    Assert ((Get-PCCpuPowerFields $ExpectedRawHex).OtherHex -ceq (Get-PCCpuPowerFields $TargetRawHex).OtherHex) 'Write changed protected bits'
    if($script:mode -eq 'native-race' -and $script:writes.Count -eq 0){Update-MockRaw (New-PCCpuPowerTargetHex $script:live 199 249)}
    if($ExpectedRawHex -cne $script:live.RawLimitHex){throw 'Native expected value conflict'}
    $script:writes.Add([pscustomobject]@{Expected=$ExpectedRawHex;Target=$TargetRawHex})
    if($script:mode -eq 'write-rejected'){throw 'Native write rejected'}
    if($script:mode -eq 'rollback-rejected' -and $script:writes.Count -gt 1){throw 'Rollback write rejected'}
    if($script:mode -eq 'partial-apply' -and $script:writes.Count -eq 1){Update-MockRaw ($ExpectedRawHex.Substring(0,8)+$TargetRawHex.Substring(8,8));return $script:live.RawLimitHex}
    Update-MockRaw $TargetRawHex
    if($script:mode -in @('bad-return','rollback-rejected') -and $script:writes.Count -eq 1){return $ExpectedRawHex}
    if($script:mode -eq 'unrelated-after-write' -and $script:writes.Count -eq 1){Update-MockRaw (New-PCCpuPowerTargetHex $script:live 199 249);return $script:live.RawLimitHex}
    $script:live.RawLimitHex
}
function Apply-Mock([int]$First=200,[int]$Second=250){Set-PCCpuPowerLimits ($script:live|Select-Object *) $First $Second $script:journal}
try{
    Reset-Mock
    $null=Apply-Mock
    $j=Read-PCCpuPowerJournal $script:journal
    Assert ($j.State -ceq 'Applied' -and $j.OriginalRawHex -ceq $script:original.RawLimitHex -and $script:live.PL1Watts -eq 200 -and $script:live.PL2Watts -eq 250) 'Apply/readback/original capture failed'
    Assert ((Get-PCCpuPowerFields $script:live.RawLimitHex).OtherHex -ceq (Get-PCCpuPowerFields $script:original.RawLimitHex).OtherHex) 'Apply changed time windows, flags or reserved bits'
    $null=Apply-Mock 180 230
    Assert ((Read-PCCpuPowerJournal $script:journal).OriginalRawHex -ceq $script:original.RawLimitHex) 'Repeated apply lost first originals'
    $null=Restore-PCCpuPowerLimits $script:journal
    Assert ($script:live.RawLimitHex -ceq $script:original.RawLimitHex -and -not (Test-Path -LiteralPath $script:journal)) 'Restore failed, including original PL2 above 253 W'

    Reset-Mock;Update-MockRaw (New-PCCpuPowerTargetHex $script:live 200 250)
    $null=Apply-Mock
    Assert ($script:writes.Count -eq 0 -and $script:saveCount -eq 0 -and -not (Test-Path -LiteralPath $script:journal)) 'Same-value apply wrote hardware or journal'

    foreach($case in 'nonadmin','stale','unsupported','missing-driver','locked','disabled','flag-mismatch','units-reserved','units-high','units-unrepresentable','nan','infinite','watts-mismatch','identity','BIOS','BootId','units-changed','missing-identity'){
        Reset-Mock;$selected=$script:live|Select-Object *
        switch($case){
            'nonadmin'{$script:admin=$false}
            'stale'{Update-MockRaw (New-PCCpuPowerTargetHex $script:live 201 251)}
            'unsupported'{$script:live.Supported=$false}
            'missing-driver'{$script:mode=$case}
            'locked'{Update-MockRaw ('8'+$script:live.RawLimitHex.Substring(1))}
            'disabled'{Update-MockRaw '00420B6000DD87D0'}
            'flag-mismatch'{$script:live.PL1Enabled=$false}
            'units-reserved'{$script:live.RawUnitsHex='00000000000A0E13'}
            'units-high'{$script:live.RawUnitsHex='10000000000A0E03'}
            'units-unrepresentable'{$script:live.RawUnitsHex='00000000000A0E0F';Update-MockRaw $script:live.RawLimitHex;$selected=$script:live|Select-Object *}
            'nan'{$script:live.PL1Watts=[double]::NaN}
            'infinite'{$script:live.PL1Watts=[double]::PositiveInfinity}
            'watts-mismatch'{$script:live.PL1Watts=200}
            'identity'{$script:live.Identity='another CPU'}
            'BIOS'{$script:live.BIOS='new BIOS'}
            'BootId'{$script:live.BootId='boot-2'}
            'units-changed'{$script:live.RawUnitsHex='00000000000A0D03'}
            'missing-identity'{$script:live.ProcessorId=''}
        }
        Reject {Set-PCCpuPowerLimits $selected 200 250 $script:journal} "Accepted $case"
        Assert ($script:writes.Count -eq 0 -and -not (Test-Path -LiteralPath $script:journal)) "Guard $case caused hardware or journal mutation"
    }
    foreach($pair in @(@('100.0','250'),@(' 100','250'),@('+100','250'),@('-100','250'),@('1e2','250'),@('NaN','250'),@('100;echo x','250'),@('2147483648','250'),@($null,'250'),@('24','250'),@('100','254'),@('251','253'),@('200','199'))){
        Reset-Mock;Reject {Set-PCCpuPowerLimits ($script:live|Select-Object *) $pair[0] $pair[1] $script:journal} 'Invalid watt input was accepted'
        Assert ($script:writes.Count -eq 0) 'Invalid watt input reached hardware'
    }
    Reset-Mock;Update-MockRaw (New-PCCpuPowerTargetHex $script:live 100 150)
    Reject {Apply-Mock 100 151} 'PL2 increase accepted'
    Reject {Apply-Mock 101 150} 'PL1 increase accepted'
    Assert ($script:writes.Count -eq 0) 'Increasing limits reached hardware'

    Reset-Mock
    Reject {Set-PCCpuPowerLimits ($script:live|Select-Object *) 200 250 (Join-Path $directory 'missing/restore.json')} 'Missing journal directory was accepted'
    Assert ($script:writes.Count -eq 0) 'Missing journal directory still allowed writes'
    Reset-Mock;$script:mode='save-pending-fails'
    Reject {Apply-Mock} 'Pending save failure was ignored'
    Assert ($script:writes.Count -eq 0) 'Pending save failure still wrote hardware'

    foreach($failureMode in 'write-rejected','bad-return','partial-apply','save-applied-fails'){
        Reset-Mock;$script:mode=$failureMode
        Reject {Apply-Mock} "Failure $failureMode was reported successful"
        Assert ($script:live.RawLimitHex -ceq $script:original.RawLimitHex -and (Read-PCCpuPowerJournal $script:journal).State -ceq 'RecoveryRequired') "Failure $failureMode did not restore and preserve recovery"
        $count=$script:writes.Count;Reject {Apply-Mock} 'Recovery required state accepted another apply'
        Assert ($script:writes.Count -eq $count) 'Recovery required state still wrote hardware'
        $script:mode='normal';$null=Restore-PCCpuPowerLimits $script:journal
        Assert (-not (Test-Path -LiteralPath $script:journal)) 'Already-restored record could not clear'
    }
    foreach($failureMode in 'prewrite-race','prewrite-lock','native-race'){
        Reset-Mock;$script:mode=$failureMode
        Reject {Apply-Mock} "Conflict $failureMode was accepted"
        Assert ($script:writes.Count -eq 0 -and (Read-PCCpuPowerJournal $script:journal).State -ceq 'RecoveryRequired') "Conflict $failureMode changed hardware or lost recovery record"
    }
    foreach($failureMode in 'rollback-rejected','readback-unavailable','unrelated-after-write'){
        Reset-Mock;$script:mode=$failureMode
        Reject {Apply-Mock} "Failure $failureMode was accepted"
        Assert ((Read-PCCpuPowerJournal $script:journal).State -ceq 'RecoveryRequired') "Failure $failureMode lost recovery record"
        if($failureMode -eq 'unrelated-after-write'){
            Assert ($script:writes.Count -eq 1 -and $script:live.PL1Watts -eq 199) 'Unknown post-write state was overwritten during rollback'
            $script:mode='normal';Reject {Restore-PCCpuPowerLimits $script:journal} 'Restore overwrote unknown external settings'
        }else{
            $script:mode='normal';$null=Restore-PCCpuPowerLimits $script:journal
            Assert ($script:live.RawLimitHex -ceq $script:original.RawLimitHex) 'Explicit recovery failed after driver became available'
        }
    }

    Reset-Mock;$null=Apply-Mock;$null=Apply-Mock 180 230
    $script:mode='bad-return';$script:writes.Clear()
    Reject {Apply-Mock 160 210} 'Failed third apply was accepted'
    Assert ($script:live.PL1Watts -eq 180 -and $script:live.PL2Watts -eq 230 -and (Read-PCCpuPowerJournal $script:journal).OriginalRawHex -ceq $script:original.RawLimitHex) 'Failed repeated apply did not roll back to prior live while retaining first originals'
    $script:mode='normal';$null=Restore-PCCpuPowerLimits $script:journal

    foreach($field in 'Identity','ProcessorId','BIOS','RawUnitsHex'){
        Reset-Mock;$null=Apply-Mock;$count=$script:writes.Count
        if($field -eq 'RawUnitsHex'){$script:live.RawUnitsHex='00000000000B0E03'}else{$script:live.$field='changed'}
        Reject {Restore-PCCpuPowerLimits $script:journal} "Restore accepted changed $field"
        Assert ($script:writes.Count -eq $count -and (Test-Path -LiteralPath $script:journal)) "Changed $field restore wrote hardware or deleted recovery"
    }
    Reset-Mock;$null=Apply-Mock;$script:live.BootId='boot-2';$count=$script:writes.Count
    Reject {Restore-PCCpuPowerLimits $script:journal} 'Saved CPU power settings replayed after reboot'
    Assert ($script:writes.Count -eq $count -and (Test-Path -LiteralPath $script:journal)) 'Cross-boot restore mutated hardware or lost record'
    Update-MockRaw $script:original.RawLimitHex;$null=Restore-PCCpuPowerLimits $script:journal
    Assert ($script:writes.Count -eq $count -and -not (Test-Path -LiteralPath $script:journal)) 'Cross-boot already-original state could not clear without a write'

    Reset-Mock;$null=Apply-Mock;$script:admin=$false;$count=$script:writes.Count
    Reject {Restore-PCCpuPowerLimits $script:journal} 'Non-admin restore allowed'
    Assert ($script:writes.Count -eq $count) 'Non-admin restore wrote hardware'
    Reset-Mock;$null=Apply-Mock;Update-MockRaw ('8'+$script:live.RawLimitHex.Substring(1));$count=$script:writes.Count
    Reject {Restore-PCCpuPowerLimits $script:journal} 'Locked restore allowed'
    Assert ($script:writes.Count -eq $count) 'Locked restore wrote hardware'
    Reset-Mock;$null=Apply-Mock;$script:mode='write-rejected'
    Reject {Restore-PCCpuPowerLimits $script:journal} 'Rejected restore reported success'
    Assert ((Read-PCCpuPowerJournal $script:journal).State -ceq 'RecoveryRequired') 'Failed restore lost recovery state'
    $script:mode='normal';$null=Restore-PCCpuPowerLimits $script:journal

    foreach($tamper in 'kind','state','missing','unrelated-original','unrelated-target','invalid-units','over-range','raises-limit','applied-state','malformed-hex'){
        Reset-Mock;$null=Apply-Mock;$j=Read-PCCpuPowerJournal $script:journal
        switch($tamper){
            'kind'{$j.Kind='Other'}
            'state'{$j.State='Unknown'}
            'missing'{$j.PSObject.Properties.Remove('BootId')}
            'unrelated-original'{$j.OriginalRawHex='00438B6000DD87D0'}
            'unrelated-target'{$j.AttemptedRawHex='004387D000DD8640'}
            'invalid-units'{$j.RawUnitsHex='00000000000A0E13'}
            'over-range'{$j.AttemptedRawHex=New-PCCpuPowerTargetHex $script:live 254 254;$j.AppliedRawHex=$j.AttemptedRawHex}
            'raises-limit'{$j.BeforeRawHex=New-PCCpuPowerTargetHex $script:live 100 150}
            'applied-state'{$j.AppliedRawHex=$j.BeforeRawHex}
            'malformed-hex'{$j.OriginalRawHex='0x1234'}
        }
        Save-PCCpuPowerJournal $j $script:journal;$count=$script:writes.Count
        Reject {Read-PCCpuPowerJournal $script:journal} "Tampered journal $tamper accepted"
        Reject {Restore-PCCpuPowerLimits $script:journal} "Tampered journal $tamper reached restore"
        Assert ($script:writes.Count -eq $count -and (Test-Path -LiteralPath $script:journal)) "Tampered journal $tamper wrote hardware or lost record"
    }
    Reset-Mock;Set-Content -LiteralPath $script:journal -Value '{invalid'
    Reject {Apply-Mock} 'Malformed JSON accepted before apply'
    Assert ($script:writes.Count -eq 0) 'Malformed JSON still allowed writes'
    'PASS: CPU power journal-before-write, exact readback, original preservation, lower-only range and bit guards, rollback, stale/admin/driver/unit/lock failures, restore, tampered journals and cross-reboot no-replay.'
}finally{Remove-Item -LiteralPath $directory -Recurse -Force}
