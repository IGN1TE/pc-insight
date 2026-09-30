$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $root 'CpuPowerNative.cs')
. (Join-Path $root 'CpuPowerNative.ps1')
$script:checks=0
function Assert($Condition,$Message){if(-not $Condition){throw $Message};$script:checks++}
function Reject([scriptblock]$Action,$Message){$caught=$false;try{& $Action}catch{$caught=$true};Assert $caught $Message}

$original='000087E8800383E8' # unit 1/8 W, PL1 125 W, PL2 253 W; firmware time/clamp bits present
$lower='0000864080038320' # PL1 100 W, PL2 200 W; preserve all other fields
$units='00000000000A0E03'
$decoded=[PCCpuPowerNative]::Decode($original,$units)
Assert ($decoded.PL1Watts -eq 125 -and $decoded.PL2Watts -eq 253) 'Power-unit scaling failed.'
Assert ($decoded.PL1Enabled -and $decoded.PL2Enabled -and -not $decoded.Locked) 'Enable/lock flags failed.'
[PCCpuPowerNative]::ValidateChange($original,$original,$lower);$script:checks++
[PCCpuPowerNative]::ValidateChange($lower,$lower,$original);$script:checks++
Reject {[PCCpuPowerNative]::ValidateChange($lower,$original,$lower)} 'Stale hardware review was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange('800087E8800383E8','800087E8800383E8','8000864080038320')} 'Firmware lock was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange('000087E8800303E8','000087E8800303E8','0000864080030320')} 'Disabled PL1 was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange('000007E8800383E8','000007E8800383E8','0000064080038320')} 'Disabled PL2 was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange($original,$original,'0000864080028320')} 'Time-window mutation was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange($original,$original,'0000864000038320')} 'Reserved bit mutation was accepted.'
Reject {[PCCpuPowerNative]::ValidateChange($original,$original,'0000864080038000')} 'Zero PL1 was accepted.'
Reject {[PCCpuPowerNative]::Decode($original,'80000000000A0E03')} 'Unexpected power-unit layout was accepted.'
Reject {[PCCpuPowerNative]::ParseHex('0x0087E8800383E8')} 'Noncanonical register text was accepted.'
Reject {[PCCpuPowerNative]::ParseHex('000087E8800383EZ')} 'Nonhex register text was accepted.'
# A firmware original can exceed the UI's apply ceiling; exact restoration remains possible.
[PCCpuPowerNative]::ValidateChange($lower,$lower,'00008FA080038FA0');$script:checks++

$bin=Join-Path $root 'vendor/PawnIO/IntelMSR.bin'
Assert ((Get-FileHash $bin -Algorithm SHA256).Hash.ToLowerInvariant() -eq [PCCpuPowerNative]::ModuleSha256) 'Signed module hash mismatch.'

# Inventory mocks prove CPU gating happens before native reads. No Windows calls are made.
$previousOs=$env:OS;$env:OS='Windows_NT'
$script:testName='13th Gen Intel(R) Core(TM) i7-13700K'
$script:testId='BFEBFBFF000B0671'
$script:testVendor='GenuineIntel'
$script:packageCount=1
function Get-CimInstance {
 param($ClassName,$OperationTimeoutSec,$ErrorAction)
 switch($ClassName){
  'Win32_Processor' {[pscustomobject]@{Name=$script:testName;Manufacturer=$script:testVendor;ProcessorId=$script:testId}}
  'Win32_ComputerSystem' {[pscustomobject]@{NumberOfProcessors=$script:packageCount}}
  'Win32_BaseBoard' {[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product='ROG STRIX Z690-A GAMING WIFI D4';SerialNumber='test-board-serial'}}
  'Win32_BIOS' {[pscustomobject]@{SMBIOSBIOSVersion='4505'}}
  'Win32_ComputerSystemProduct' {[pscustomobject]@{UUID='5b406dd4-52ea-49b3-9843-03545bc65678'}}
  'Win32_OperatingSystem' {[pscustomobject]@{LastBootUpTime=[datetime]'2026-09-30T10:00:00Z'}}
  default {throw 'Unexpected inventory class.'}
 }
}
try {
 $inventory=Get-PCCpuPowerInventory
 Assert ($inventory.Identity -match '^[0-9a-f]{64}$' -and $inventory.Identity -notmatch 'test-board-serial') 'Stable private identity was not hashed.'
 Assert ($inventory.BIOS -eq '4505' -and $inventory.ProcessorId -eq $script:testId -and $inventory.BootId) 'Identity fields missing.'
 $script:testName='13th Gen Intel(R) Core(TM) i7-13700KF'
 $rejected=Get-PCCpuPowerHardware
 Assert (-not $rejected.Supported -and $null -eq $rejected.RawLimitHex -and $rejected.Reason -match 'only Intel Core i7-13700K') 'Unsupported model was not rejected before MSR access.'
 Reject {Set-PCCpuPowerHardware -ExpectedRawHex $original -TargetRawHex $lower} 'Unsupported model reached write.'
 $script:testName='13th Gen Intel(R) Core(TM) i7-13700K';$script:testId='BFEBFBFF00090672'
 Reject {Get-PCCpuPowerInventory} 'Incorrect family/model signature was accepted.'
 $script:testId='BFEBFBFF000B0671';$script:testVendor='AuthenticAMD'
 Reject {Get-PCCpuPowerInventory} 'Incorrect CPU vendor was accepted.'
 $script:testVendor='GenuineIntel';$script:packageCount=2
 Reject {Get-PCCpuPowerInventory} 'Multiple CPU packages were accepted.'
}finally{$env:OS=$previousOs}
Write-Host "CPU power native: $script:checks checks passed. Offline only; no physical CPU/driver operations performed."
