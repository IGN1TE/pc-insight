# CPU package power transactions. Hardware access is supplied by CpuPowerNative.ps1.
# Only PL1/PL2 power fields may change; voltage, ratios, time windows and flags are preserved.
function Test-PCCpuPowerAdministrator {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function ConvertTo-PCCpuPowerHex($Value) {
    if($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-fA-F]{16}$'){throw 'CPU power register data is invalid. No settings were changed.'}
    $Value.ToUpperInvariant()
}
function Get-PCCpuPowerFields($RawHex) {
    $hex=ConvertTo-PCCpuPowerHex $RawHex
    # Parse independent 32-bit halves: Windows PowerShell signed shifts must not alter bit 63.
    $high=[Convert]::ToUInt32($hex.Substring(0,8),16);$low=[Convert]::ToUInt32($hex.Substring(8,8),16)
    [pscustomobject]@{Hex=$hex;High=$high;Low=$low;PL1Raw=($low -band 32767);PL2Raw=($high -band 32767);PL1Enabled=(($low -band 32768) -ne 0);PL2Enabled=(($high -band 32768) -ne 0);Locked=(($high -band [uint32]2147483648) -ne 0);OtherHex=('{0:X8}{1:X8}' -f ($high -band [uint32]4294934528),($low -band [uint32]4294934528))}
}
function Get-PCCpuPowerUnit($RawUnitsHex) {
    $hex=ConvertTo-PCCpuPowerHex $RawUnitsHex
    $high=[Convert]::ToUInt32($hex.Substring(0,8),16);$low=[Convert]::ToUInt32($hex.Substring(8,8),16)
    # Intel RAPL_POWER_UNIT: power bits 3:0, energy bits 12:8, time bits 19:16.
    if($high -ne 0 -or ($low -band [uint32]4293976304) -ne 0){throw 'CPU power units contain unexpected reserved bits. No settings were changed.'}
    [Math]::Pow(2,-[int]($low -band 15))
}
function ConvertTo-PCCpuPowerWatts($Value) {
    $number=0
    if($null -eq $Value -or [string]$Value -cnotmatch '^[0-9]+$' -or -not [int]::TryParse([string]$Value,[ref]$number) -or $number -lt 25 -or $number -gt 253){throw 'Enter whole watts from 25 through 253 for each CPU power limit.'}
    $number
}
function Assert-PCCpuPowerMetadata($Value) {
    foreach($field in 'Identity','ProcessorId','BIOS','BootId'){
        if($Value.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Value.$field) -or $Value.$field.Length -gt 512){throw "CPU $field information is missing or invalid. Detect CPU power support again."}
    }
}
function Assert-PCCpuPowerSameHardware($Expected,$Actual,[switch]$AllowDifferentBoot) {
    Assert-PCCpuPowerMetadata $Expected;Assert-PCCpuPowerMetadata $Actual
    foreach($field in 'Identity','ProcessorId','BIOS'){
        if($Expected.$field -cne $Actual.$field){throw 'CPU identity or BIOS changed. Saved power settings cannot be used on this hardware.'}
    }
    if(-not $AllowDifferentBoot -and $Expected.BootId -cne $Actual.BootId){throw 'Windows has restarted. Saved CPU power settings will not be replayed across a reboot.'}
    if((ConvertTo-PCCpuPowerHex $Expected.RawUnitsHex) -cne (ConvertTo-PCCpuPowerHex $Actual.RawUnitsHex)){throw 'CPU power units changed. Detect support again; saved settings cannot be replayed.'}
}
function Assert-PCCpuPowerHardware($Hardware,[switch]$AllowLocked) {
    if(-not $Hardware -or $Hardware.Supported -isnot [bool] -or -not $Hardware.Supported){
        $reason=if($Hardware -and -not [string]::IsNullOrWhiteSpace([string]$Hardware.Reason)){[string]$Hardware.Reason}else{'The supported CPU power backend is unavailable.'}
        throw ('CPU power control is unavailable: '+$reason)
    }
    Assert-PCCpuPowerMetadata $Hardware
    $fields=Get-PCCpuPowerFields $Hardware.RawLimitHex;$unit=Get-PCCpuPowerUnit $Hardware.RawUnitsHex
    foreach($flag in 'Locked','PL1Enabled','PL2Enabled'){
        if($Hardware.$flag -isnot [bool] -or $Hardware.$flag -ne $fields.$flag){throw 'CPU power flags do not agree with the register readback.'}
    }
    if(-not $fields.PL1Enabled -or -not $fields.PL2Enabled){throw 'Both existing CPU power limits must already be enabled. PC Insight does not change enable flags.'}
    if($fields.Locked -and -not $AllowLocked){throw 'CPU package power settings are locked by firmware. No write is allowed.'}
    foreach($limit in 'PL1','PL2'){
        $watts=0.0
        if($null -eq $Hardware.($limit+'Watts') -or -not [double]::TryParse([string]$Hardware.($limit+'Watts'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$watts) -or [double]::IsNaN($watts) -or [double]::IsInfinity($watts) -or $watts -le 0 -or $fields.($limit+'Raw') -eq 0 -or $watts -ne ($unit*$fields.($limit+'Raw'))){throw 'CPU power values do not agree with the register units and readback.'}
    }
}
function New-PCCpuPowerTargetHex($Hardware,[int]$PL1,[int]$PL2) {
    $fields=Get-PCCpuPowerFields $Hardware.RawLimitHex;$unit=Get-PCCpuPowerUnit $Hardware.RawUnitsHex
    $first=$PL1/$unit;$second=$PL2/$unit
    if($first -ne [Math]::Floor($first) -or $second -ne [Math]::Floor($second) -or $first -lt 1 -or $second -lt 1 -or $first -gt 32767 -or $second -gt 32767){throw 'The requested whole-watt limits cannot be represented by this CPU power unit.'}
    '{0:X8}{1:X8}' -f (($fields.High -band [uint32]4294934528) -bor [uint32]$second),(($fields.Low -band [uint32]4294934528) -bor [uint32]$first)
}
function Save-PCCpuPowerJournal($Journal,[Alias('Path')][string]$JournalPath) {
    $full=[IO.Path]::GetFullPath($JournalPath);$temporary=Join-Path ([IO.Path]::GetDirectoryName($full)) ([IO.Path]::GetRandomFileName())
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Journal|ConvertTo-Json -Depth 5))
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if([IO.File]::Exists($full)){[IO.File]::Replace($temporary,$full,[NullString]::Value)}else{[IO.File]::Move($temporary,$full)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Read-PCCpuPowerJournal([Alias('Path')][string]$JournalPath) {
    $j=Get-Content -LiteralPath $JournalPath -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if($j.Schema -ne 1 -or $j.Kind -cne 'PCInsight.CpuPackagePower' -or $j.State -cnotin @('Pending','Applied','RecoveryRequired','Restoring')){throw 'CPU power recovery record is invalid. No settings were changed.'}
    Assert-PCCpuPowerMetadata $j;$null=Get-PCCpuPowerUnit $j.RawUnitsHex
    $original=Get-PCCpuPowerFields $j.OriginalRawHex
    if($original.Locked -or -not $original.PL1Enabled -or -not $original.PL2Enabled -or $original.PL1Raw -eq 0 -or $original.PL2Raw -eq 0){throw 'Original CPU power recovery data is invalid.'}
    foreach($field in 'BeforeRawHex','AttemptedRawHex','AppliedRawHex'){
        $item=Get-PCCpuPowerFields $j.$field
        if($item.OtherHex -cne $original.OtherHex -or $item.PL1Raw -lt 1 -or $item.PL2Raw -lt 1 -or $item.PL1Raw -gt $original.PL1Raw -or $item.PL2Raw -gt $original.PL2Raw){throw 'CPU power recovery record changes protected bits or exceeds the captured original limits.'}
    }
    $before=Get-PCCpuPowerFields $j.BeforeRawHex;$attempted=Get-PCCpuPowerFields $j.AttemptedRawHex
    $unit=Get-PCCpuPowerUnit $j.RawUnitsHex
    if($attempted.PL1Raw -gt $before.PL1Raw -or $attempted.PL2Raw -gt $before.PL2Raw -or $attempted.PL1Raw -gt $attempted.PL2Raw){throw 'CPU power recovery record contains an invalid apply transaction.'}
    foreach($raw in @($attempted.PL1Raw,$attempted.PL2Raw)){
        $watts=$raw*$unit
        if($watts -lt 25 -or $watts -gt 253 -or $watts -ne [Math]::Floor($watts)){throw 'CPU power recovery target is outside the preview range.'}
    }
    if($j.AppliedRawHex -cne $j.BeforeRawHex -and $j.AppliedRawHex -cne $j.AttemptedRawHex){throw 'CPU power recovery record has no verified previous state.'}
    if($j.State -ceq 'Applied' -and $j.AppliedRawHex -cne $j.AttemptedRawHex){throw 'CPU power recovery record has an inconsistent applied state.'}
    $j
}
function Test-PCCpuPowerKnownState($Journal,$RawHex) {
    $current=Get-PCCpuPowerFields $RawHex;$before=Get-PCCpuPowerFields $Journal.BeforeRawHex;$attempted=Get-PCCpuPowerFields $Journal.AttemptedRawHex;$original=Get-PCCpuPowerFields $Journal.OriginalRawHex
    if($current.OtherHex -cne $original.OtherHex){return $false}
    if($current.Hex -ceq $original.Hex){return $true}
    # A rejected/clamped write may affect only one power field; never adopt an unrelated value.
    ($current.PL1Raw -in @($before.PL1Raw,$attempted.PL1Raw)) -and ($current.PL2Raw -in @($before.PL2Raw,$attempted.PL2Raw))
}
function Invoke-PCCpuPowerWrite($Expected,[string]$TargetRawHex,[ref]$WriteAttempted) {
    $live=Get-PCCpuPowerHardware;Assert-PCCpuPowerHardware $live;Assert-PCCpuPowerSameHardware $Expected $live
    if((ConvertTo-PCCpuPowerHex $live.RawLimitHex) -cne (ConvertTo-PCCpuPowerHex $Expected.RawLimitHex)){throw 'CPU power settings changed immediately before writing. Detect support again.'}
    $target=Get-PCCpuPowerFields $TargetRawHex;$before=Get-PCCpuPowerFields $live.RawLimitHex
    if($target.OtherHex -cne $before.OtherHex){throw 'CPU power transaction attempted to change protected register bits.'}
    $WriteAttempted.Value=$true
    $readback=ConvertTo-PCCpuPowerHex (Set-PCCpuPowerHardware -ExpectedRawHex $before.Hex -TargetRawHex $target.Hex)
    if($readback -cne $target.Hex){throw 'CPU power register readback did not match the requested limits.'}
    $verified=Get-PCCpuPowerHardware;Assert-PCCpuPowerHardware $verified;Assert-PCCpuPowerSameHardware $live $verified
    if((ConvertTo-PCCpuPowerHex $verified.RawLimitHex) -cne $target.Hex){throw 'CPU power limits changed during verification.'}
    $verified
}
function Set-PCCpuPowerLimits($Selected,$PL1,$PL2,[string]$JournalPath) {
    if(-not (Test-PCCpuPowerAdministrator)){throw 'Reopen PC Insight as administrator to apply CPU power limits.'}
    $first=ConvertTo-PCCpuPowerWatts $PL1;$second=ConvertTo-PCCpuPowerWatts $PL2
    if($first -gt $second){throw 'PL1 must not exceed PL2.'}
    Assert-PCCpuPowerHardware $Selected
    $live=Get-PCCpuPowerHardware;Assert-PCCpuPowerHardware $live;Assert-PCCpuPowerSameHardware $Selected $live
    if((ConvertTo-PCCpuPowerHex $Selected.RawLimitHex) -cne (ConvertTo-PCCpuPowerHex $live.RawLimitHex)){throw 'CPU power settings changed since detection. Detect support again before applying.'}
    if($first -gt $live.PL1Watts -or $second -gt $live.PL2Watts){throw 'This preview only lowers or retains each current CPU power limit. Raising limits is unavailable.'}
    $target=New-PCCpuPowerTargetHex $live $first $second;$journal=$null
    if(Test-Path -LiteralPath $JournalPath){
        $journal=Read-PCCpuPowerJournal $JournalPath;Assert-PCCpuPowerSameHardware $journal $live
        if($journal.State -cne 'Applied' -or (ConvertTo-PCCpuPowerHex $journal.AppliedRawHex) -cne (ConvertTo-PCCpuPowerHex $live.RawLimitHex)){throw 'Restore the saved CPU power limits before applying again. The recovery record or current settings need attention.'}
    }
    if($target -ceq (ConvertTo-PCCpuPowerHex $live.RawLimitHex)){return 'CPU power limits already match. No hardware or recovery record changes were made.'}
    if(-not $journal){
        $journal=[pscustomobject]@{Schema=1;Kind='PCInsight.CpuPackagePower';State='Pending';Name=$live.Name;Identity=$live.Identity;ProcessorId=$live.ProcessorId;BIOS=$live.BIOS;BootId=$live.BootId;RawUnitsHex=(ConvertTo-PCCpuPowerHex $live.RawUnitsHex);OriginalRawHex=(ConvertTo-PCCpuPowerHex $live.RawLimitHex);BeforeRawHex=(ConvertTo-PCCpuPowerHex $live.RawLimitHex);AttemptedRawHex=$target;AppliedRawHex=(ConvertTo-PCCpuPowerHex $live.RawLimitHex);Created=([datetimeoffset]::UtcNow.ToString('o'))}
    }
    $journal.State='Pending';$journal.BeforeRawHex=ConvertTo-PCCpuPowerHex $live.RawLimitHex;$journal.AttemptedRawHex=$target
    Save-PCCpuPowerJournal $journal $JournalPath
    $attempted=$false
    try{
        $verified=Invoke-PCCpuPowerWrite $live $target ([ref]$attempted)
        $journal.State='Applied';$journal.AppliedRawHex=$target;Save-PCCpuPowerJournal $journal $JournalPath
        "Applied and read back CPU package limits: PL1 $($verified.PL1Watts) W, PL2 $($verified.PL2Watts) W. Original limits are saved. Register readback does not establish performance or stability."
    }catch{
        $problem=$_.Exception.Message;$recovery='No write was attempted. The recovery record remains.'
        if($attempted){
            try{
                $current=Get-PCCpuPowerHardware;Assert-PCCpuPowerHardware $current;Assert-PCCpuPowerSameHardware $live $current
                if(-not (Test-PCCpuPowerKnownState $journal $current.RawLimitHex)){throw 'Current power settings do not match this transaction.'}
                if((ConvertTo-PCCpuPowerHex $current.RawLimitHex) -cne (ConvertTo-PCCpuPowerHex $live.RawLimitHex)){$rollbackAttempted=$false;$null=Invoke-PCCpuPowerWrite $current $live.RawLimitHex ([ref]$rollbackAttempted)}
                $recovery='Previous limits were restored and read back. Use Restore original limits to finish recovery.'
            }catch{$recovery='Recovery could not be verified. The original limits remain saved; check Restore original limits.'}
        }
        $journal.State='RecoveryRequired';try{Save-PCCpuPowerJournal $journal $JournalPath}catch{}
        throw "$problem $recovery"
    }
}
function Restore-PCCpuPowerLimits([string]$JournalPath) {
    if(-not (Test-PCCpuPowerAdministrator)){throw 'Reopen PC Insight as administrator to restore CPU power limits.'}
    $journal=Read-PCCpuPowerJournal $JournalPath
    $live=Get-PCCpuPowerHardware;Assert-PCCpuPowerHardware $live -AllowLocked;Assert-PCCpuPowerSameHardware $journal $live -AllowDifferentBoot
    $current=ConvertTo-PCCpuPowerHex $live.RawLimitHex;$original=ConvertTo-PCCpuPowerHex $journal.OriginalRawHex
    # Reboot never authorizes replay. Clearing a verified already-original record requires no write.
    if($current -ceq $original){Remove-Item -LiteralPath $JournalPath -ErrorAction Stop;return 'Original CPU power limits are already present and verified. The recovery record was cleared.'}
    Assert-PCCpuPowerSameHardware $journal $live;Assert-PCCpuPowerHardware $live
    if(-not (Test-PCCpuPowerKnownState $journal $current)){throw 'CPU power settings changed outside this transaction. No restore was written; the recovery record remains.'}
    $journal.State='Restoring';Save-PCCpuPowerJournal $journal $JournalPath
    $attempted=$false
    try{
        # Recovery may raise a reduced limit back to its first original, including originals above 253 W.
        $verified=Invoke-PCCpuPowerWrite $live $original ([ref]$attempted)
        Remove-Item -LiteralPath $JournalPath -ErrorAction Stop
        "Restored and read back original CPU package limits: PL1 $($verified.PL1Watts) W, PL2 $($verified.PL2Watts) W."
    }catch{
        $journal.State='RecoveryRequired';try{Save-PCCpuPowerJournal $journal $JournalPath}catch{}
        throw ('CPU power restoration could not be completed: '+$_.Exception.Message+' The recovery record remains.')
    }
}
