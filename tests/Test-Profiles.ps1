$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Power.ps1"
. "$PSScriptRoot/../Profiles.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pc-profiles-'+[guid]::NewGuid())
try{
 $b=[pscustomobject]@{Schema=1;Created='2026-01-01';Benchmarks=@([pscustomobject]@{Test='Example';MiBPerSecond=123});Sessions=@()}
 $one=Save-PCNamedProfile $folder 'Original settings' $b
 $two=Save-PCNamedProfile $folder 'Original settings' $b
 Assert ($one.ID -ne $two.ID) 'Same label must not overwrite profiles'
 $b.Created='2026-01-02'
 $read=Read-PCNamedProfile $folder $one.ID
 Assert ($read.Baseline.Created -eq '2026-01-01' -and $read.Baseline.Benchmarks[0].MiBPerSecond -eq 123) 'Saved snapshot must remain independent'
 Assert (@(Get-PCNamedProfiles $folder).Count -eq 2) 'Profile discovery failed'
 $blocked=$false;try{$null=Read-PCNamedProfile $folder '../other'}catch{$blocked=$true}
 Assert $blocked 'Profile lookup must reject path traversal'
 $blocked=$false;try{$null=Save-PCNamedProfile $folder '' $b}catch{$blocked=$true}
 Assert $blocked 'Empty name must be rejected'
 'PASS: independent profile roundtrip, duplicate names, listing and invalid inputs'
}finally{if(Test-Path $folder){Remove-Item $folder -Recurse -Force}}
