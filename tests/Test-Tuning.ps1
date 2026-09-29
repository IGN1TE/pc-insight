$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Power.ps1"
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
. "$PSScriptRoot/../Tuning.ps1"
function Assert($ok,$msg){if(-not $ok){throw $msg}}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-tuning-'+[guid]::NewGuid());$null=New-Item -ItemType Directory $dir
$script:testJournalPath=Join-Path $dir 'restore.json';$script:testBaselinePath=Join-Path $dir 'baseline.json'
$script:watts=400.0;$script:writes=0;$script:ignore=$false
function Invoke-PCNvidia([string[]]$Arguments){
 if($Arguments[0] -like '--query*'){return "GPU-12345678-abcd-abcd-abcd-123456789012, NVIDIA Example, 1, $script:watts, 400, 200, 500"}
 Assert ($Arguments[0] -eq '-i' -and $Arguments[1] -eq 'GPU-12345678-abcd-abcd-abcd-123456789012') 'Every write must target exact UUID'
 Assert ((Test-Path $script:testJournalPath) -and (Test-Path $script:testBaselinePath)) 'Recovery and baseline must exist before write'
 $script:writes++
 if($script:ignore){$script:ignore=$false;return 'ignored'}
 $script:watts=[double]::Parse($Arguments[3],[Globalization.CultureInfo]::InvariantCulture)
 return 'ok'
}
try{
 $d=@(Get-PCPowerDevices)[0]
 Assert ($d.Available -and $d.Current -eq 400) 'Capability parse failed'
 $b=[pscustomobject]@{Schema=1;Created='2026-01-02';Benchmarks=@();Sessions=@()}
 $null=Set-PCPowerReduction $d 90 $script:testJournalPath $script:testBaselinePath $b
 Assert ($script:watts -eq 360 -and (Read-PCPowerJournal $script:testJournalPath).OriginalWatts -eq 400) 'Apply or original preservation failed'
 $staleRejected=$false;try{$null=Set-PCPowerReduction $d 80 $script:testJournalPath $script:testBaselinePath $b}catch{$staleRejected=$true}
 Assert ($staleRejected -and $script:writes -eq 1) 'Stale display must not write'
 $d=@(Get-PCPowerDevices)[0];$null=Set-PCPowerReduction $d 80 $script:testJournalPath $script:testBaselinePath $b
 Assert ($script:watts -eq 320 -and (Read-PCPowerJournal $script:testJournalPath).OriginalWatts -eq 400) 'Preset must be relative to original'
 $d=@(Get-PCPowerDevices)[0];$blocked=$false;try{$null=Set-PCPowerReduction $d 90 $script:testJournalPath $script:testBaselinePath $b}catch{$blocked=$true}
 Assert $blocked 'Preset cannot raise active cap'
 $null=Restore-PCPower $script:testJournalPath
 Assert ($script:watts -eq 400 -and -not (Test-Path $script:testJournalPath)) 'Restore verification and cleanup failed'
 $d=@(Get-PCPowerDevices)[0];$script:ignore=$true;$rejected=$false
 try{$null=Set-PCPowerReduction $d 90 $script:testJournalPath $script:testBaselinePath $b}catch{$rejected=$_.Exception.Message -match 'Previous limit restored'}
 Assert ($rejected -and $script:watts -eq 400 -and (Test-Path $script:testJournalPath)) 'Read-back failure must rollback and retain journal'
 Assert ($null -eq (Convert-PCWatts 'N/A')) 'Unavailable values must not be zero'
 $a=[pscustomobject]@{Test='CPU';Timestamp='2026-01-01';CPUName='CPU';Runtime='4';Workers=1;MiBPerSecond=100;Completed=$true}
 $c=$a.PSObject.Copy();$c.Timestamp='2026-01-03';$c.MiBPerSecond=90
 $b.Benchmarks=@($a)
 Assert ((Get-PCBaselineComparison $b @($c) @()) -match 'INSUFFICIENT BASELINE') 'Single-run baseline must not generate tuning verdict'
 'PASS: device identity, capability parsing, journal-before-write, stale settings, preset bounds, original preservation, verified restore, rollback and baseline comparison'
}finally{Remove-Item $dir -Recurse -Force}
