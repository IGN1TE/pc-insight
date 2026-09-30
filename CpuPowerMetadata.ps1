# Pure recorded CPU power context. This module never reads or writes hardware.
function Test-PCRecordedCpuPower($CpuPower) {
    if(-not $CpuPower -or $CpuPower.Available -isnot [bool] -or -not $CpuPower.Available){return $false}
    if([string]::IsNullOrWhiteSpace([string]$CpuPower.Identity)){return $false}
    foreach($field in @('RawLimitHex','RawUnitsHex')){
        if([string]$CpuPower.$field -notmatch '^(0x)?[0-9a-fA-F]{1,16}$'){return $false}
    }
    foreach($field in @('PL1Watts','PL2Watts')){
        $number=0.0
        if(-not [double]::TryParse([string]$CpuPower.$field,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0){return $false}
    }
    foreach($field in @('Locked','PL1Enabled','PL2Enabled')){if($CpuPower.$field -isnot [bool]){return $false}}
    return $true
}
function Get-PCRecordedCpuPowerSignature($State) {
    $cpu=$State.CpuPower
    if(-not (Test-PCRecordedCpuPower $cpu)){return 'CPU limits unavailable'}
    # Use the whole package register, units and identity. This includes enable/lock,
    # clamp and time-window changes even when PL1/PL2 watt values are unchanged.
    $limit=([string]$cpu.RawLimitHex -replace '^0x','').PadLeft(16,'0').ToUpperInvariant()
    $units=([string]$cpu.RawUnitsHex -replace '^0x','').PadLeft(16,'0').ToUpperInvariant()
    'CPU limits: '+$cpu.Identity+'; units='+$units+'; package='+$limit
}
function Get-PCRecordedCpuPowerContext($State) {
    $cpu=$State.CpuPower
    if(-not (Test-PCRecordedCpuPower $cpu)){return 'CPU limits unavailable'}
    $pl1=[double]::Parse([string]$cpu.PL1Watts,[Globalization.CultureInfo]::InvariantCulture)
    $pl2=[double]::Parse([string]$cpu.PL2Watts,[Globalization.CultureInfo]::InvariantCulture)
    'CPU limits: PL1 {0:N1} W ({1}), PL2 {2:N1} W ({3}); register {4}.' -f $pl1,$(if($cpu.PL1Enabled){'enabled'}else{'disabled'}),$pl2,$(if($cpu.PL2Enabled){'enabled'}else{'disabled'}),$(if($cpu.Locked){'locked'}else{'unlocked'})
}
