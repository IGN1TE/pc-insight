# Limited, fresh hardware probe for the first CPU package-power control implementation.
# Ratio, voltage, firmware locks and enable/clamp/time fields are never modified.
$script:pcCpuPowerNativeRoot = $PSScriptRoot

function Get-PCCpuPowerInventory {
    if($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8){throw 'CPU power control requires 64-bit Windows PowerShell.'}
    $cpus=@(Get-CimInstance Win32_Processor -OperationTimeoutSec 5 -ErrorAction Stop)
    $systems=@(Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction Stop)
    if($cpus.Count -ne 1 -or $systems.Count -ne 1 -or [int]$systems[0].NumberOfProcessors -ne 1){throw 'CPU power control requires exactly one physical processor package.'}
    $cpu=$cpus[0];$name=([string]$cpu.Name).Trim();$id=([string]$cpu.ProcessorId).Trim().ToUpperInvariant()
    if(([string]$cpu.Manufacturer).Trim() -cne 'GenuineIntel' -or $name -notmatch '(?i)\bi7-13700K\b'){
        throw 'CPU package power control currently supports only Intel Core i7-13700K; no registers were accessed.'
    }
    if($id -notmatch '^[0-9A-F]{16}$'){throw 'CPU CPUID identity is unavailable; no registers were accessed.'}
    $signature=[Convert]::ToUInt32($id.Substring(8),16)
    $family=($signature -shr 8) -band 15;$model=(($signature -shr 4) -band 15) -bor (($signature -shr 12) -band 240)
    if($family -ne 6 -or $model -ne 0xB7 -or (($signature -shr 20) -band 255) -ne 0){
        throw 'CPU model signature is not the supported family 6 / model B7. No registers were accessed.'
    }
    $boards=@(Get-CimInstance Win32_BaseBoard -OperationTimeoutSec 5 -ErrorAction Stop)
    $firmware=@(Get-CimInstance Win32_BIOS -OperationTimeoutSec 5 -ErrorAction Stop)
    $products=@(Get-CimInstance Win32_ComputerSystemProduct -OperationTimeoutSec 5 -ErrorAction Stop)
    $systemsOs=@(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop)
    if($boards.Count -ne 1 -or $firmware.Count -ne 1 -or $products.Count -ne 1 -or $systemsOs.Count -ne 1){throw 'A unique motherboard, BIOS, system and boot identity could not be obtained.'}
    $uuid=[guid]::Empty
    if(-not [guid]::TryParse([string]$products[0].UUID,[ref]$uuid) -or $uuid -eq [guid]::Empty -or $uuid.ToString() -eq 'ffffffff-ffff-ffff-ffff-ffffffffffff'){
        throw 'The firmware system UUID is unavailable; power changes cannot be tied to this PC.'
    }
    $board=(@(([string]$boards[0].Manufacturer).Trim(),([string]$boards[0].Product).Trim()) -join ' ').Trim()
    $bios=([string]$firmware[0].SMBIOSBIOSVersion).Trim()
    if(-not $board -or -not $bios -or -not $systemsOs[0].LastBootUpTime){throw 'Motherboard, BIOS or boot identity is incomplete.'}
    $boot=([datetime]$systemsOs[0].LastBootUpTime).ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    $identityText=(@($uuid.ToString('D'),$board,([string]$boards[0].SerialNumber).Trim(),$id) -join "`n")
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$identity=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identityText)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    [pscustomobject]@{Name=$name;Identity=$identity;ProcessorId=$id;BIOS=$bios;BootId=$boot;Board=$board}
}

function Initialize-PCCpuPowerNative {
    if(-not ('PCCpuPowerNative' -as [type])){Add-Type -Path (Join-Path $script:pcCpuPowerNativeRoot 'CpuPowerNative.cs') -ErrorAction Stop}
}

function Get-PCCpuPowerHardware {
    $result=[ordered]@{Name=$null;Identity=$null;ProcessorId=$null;BIOS=$null;BootId=$null;Board=$null;RawLimitHex=$null;RawUnitsHex=$null;Supported=$false;Reason=$null;PL1Watts=$null;PL2Watts=$null;Locked=$null;PL1Enabled=$null;PL2Enabled=$null}
    try {
        # Inventory and exact CPU validation precede module loading and all MSR access.
        $inventory=Get-PCCpuPowerInventory
        foreach($key in @('Name','Identity','ProcessorId','BIOS','BootId','Board')){$result[$key]=$inventory.$key}
        Initialize-PCCpuPowerNative
        $module=Join-Path $script:pcCpuPowerNativeRoot 'vendor\PawnIO\IntelMSR.bin'
        $raw=[PCCpuPowerNative]::Read($module)
        foreach($key in @('RawLimitHex','RawUnitsHex','PL1Watts','PL2Watts','Locked','PL1Enabled','PL2Enabled')){$result[$key]=$raw.$key}
        if($raw.Locked){$result.Reason='The firmware locked CPU package power limits. PC Insight will not unlock them.'}
        elseif(-not $raw.PL1Enabled -or -not $raw.PL2Enabled){$result.Reason='Both package power limits must already be enabled by firmware; PC Insight does not enable disabled limits.'}
        elseif($raw.PL1Watts -le 0 -or $raw.PL2Watts -le 0){$result.Reason='CPU package power values are zero or invalid; control is unavailable.'}
        else {$result.Supported=$true;$result.Reason='Live MSR package-power values read. Only reductions to the two enabled wattage limits are available; firmware may impose additional limits.'}
    } catch {$result.Supported=$false;$result.Reason=$_.Exception.Message}
    [pscustomobject]$result
}

function Set-PCCpuPowerHardware {
    param([Parameter(Mandatory=$true)][string]$ExpectedRawHex,[Parameter(Mandatory=$true)][string]$TargetRawHex)
    # Revalidate the physical processor on every write, including restoration.
    $null=Get-PCCpuPowerInventory
    Initialize-PCCpuPowerNative
    $module=Join-Path $script:pcCpuPowerNativeRoot 'vendor\PawnIO\IntelMSR.bin'
    [PCCpuPowerNative]::Write($module,$ExpectedRawHex,$TargetRawHex)
}
