$ErrorActionPreference='Stop'
. "$PSScriptRoot/../CpuTuning.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Snapshot($name,$maker='GenuineIntel'){
 [pscustomobject]@{Timestamp='2026-09-30T12:00:00Z';CPU=@([pscustomobject]@{Name=$name;Manufacturer=$maker});Board=@([pscustomobject]@{Manufacturer='Test board vendor';Product='Z690 model'});BIOS=@([pscustomobject]@{SMBIOSBIOSVersion='1234'})}
}
foreach($name in '13th Gen Intel(R) Core(TM) i7-13700K','Intel Core i9-12900KS','Intel Core i5-13600KF','Intel Core Ultra 9 285K'){
 $r=Get-PCCpuTuningReadiness (Snapshot $name)
 Assert ($r.ModelCandidate -and -not $r.CanWrite -and $r.CanBenchmark) "Candidate classification failed: $name"
 Assert ($r.Reason -match 'not verified write support') 'Candidate implied hardware support'
}
foreach($name in 'Intel Core i7-13700','Intel Core i7-13700H','Intel Xeon W-2295','Intel Core i7-13700K_FAKE'){
 $r=Get-PCCpuTuningReadiness (Snapshot $name);Assert (-not $r.ModelCandidate -and -not $r.CanWrite) "Unrecognized name inferred support: $name"
}
$r=Get-PCCpuTuningReadiness (Snapshot 'AMD Ryzen 7 7800X3D' 'AuthenticAMD');Assert ($r.Vendor -eq 'AMD' -and -not $r.ModelCandidate -and -not $r.CanWrite) 'AMD inferred write capability'
$r=Get-PCCpuTuningReadiness $null;Assert (-not $r.CanBenchmark -and -not $r.CanWrite -and -not $r.CPUName) 'Missing scan enabled controls'
$s=Snapshot 'Intel Core i7-13700K';$s.CPU+=@($s.CPU[0]);$r=Get-PCCpuTuningReadiness $s;Assert (-not $r.CanBenchmark -and -not $r.ModelCandidate -and $r.Reason -match 'Multiple') 'Multi-CPU support inferred'
$r=Get-PCCpuTuningReadiness (Snapshot 'Unknown' 'Unknown');Assert ($r.Vendor -eq 'Unknown' -and -not $r.VendorRequirementsUrl) 'Unknown vendor produced URL'
$r=Get-PCCpuTuningReadiness (Snapshot 'Intel Core i7-13700K');Assert ((Format-PCCpuTuningReadiness $r) -match '1234' -and $r.SnapshotTimestamp -eq '2026-09-30T12:00:00Z') 'Snapshot provenance missing'
Assert (@($r.Controls|Where-Object Control -match 'multiplier|voltage|package').Count -eq 3) 'Hardware control rows missing'
'PASS: Intel suffix candidates, unrecognized/mobile/AMD/unknown/multiple/missing CPU cases, inventory provenance and unavailable write capabilities'
