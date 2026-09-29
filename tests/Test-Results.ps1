$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../Power.ps1"
function Assert($ok,$message) { if (-not $ok) { throw $message } }
$a = [pscustomobject]@{Test='parallel'; Timestamp='2026-01-01'; CPUName='CPU'; Runtime='4'; Workers=16; MiBPerSecond=100; Completed=$true; Plan='A'}
$b = [pscustomobject]@{Test='parallel'; Timestamp='2026-01-03'; CPUName='CPU'; Runtime='4'; Workers=16; MiBPerSecond=101; Completed=$true; Plan='B'; Seconds=20; Frames=@([pscustomobject]@{Provider='Built-in'; Sensors=@([pscustomobject]@{Parent='/intelcpu/0';Name='Distance to TjMax';Type='Temperature';Value=90},[pscustomobject]@{Parent='/intelcpu/0';Name='CPU Package';Type='Temperature';Value=35})})}
$c = [pscustomobject]@{Test='single'; Timestamp='2026-01-02'; CPUName='CPU'; Runtime='4'; Workers=1; MiBPerSecond=500; Completed=$true}
Assert ((Get-PCPreviousMatch $b @($a,$c)).Timestamp -eq $a.Timestamp) 'Must skip incompatible intervening test'
$t = Get-PCSessionSummary $b @($a,$c,$b)
Assert ($t -match '35.0 C' -and $t -notmatch '90.0 C') 'Headroom must not count as temperature'
Assert ($t -match 'Power plan changed' -and $t -match '\+1.0%') 'Comparison and plan difference missing'
Assert ($t -match 'Peak CPU package power: Unavailable') 'Missing power must not become zero'
$b.Completed=$false
Assert ((Get-PCComparison $b @($a)) -eq 'No comparable score for this session.') 'Failed test must not be compared'
$flat = @(Expand-PCHistory @(@{value=@(@{value=@($a,$b);Count=2});Count=1}))
Assert ($flat.Count -eq 2) 'Nested sessions must recover'
'Results tests passed'
