$ErrorActionPreference='Stop'
foreach($module in 'Results','SessionExport','SessionDetails','RepeatedTests','SessionComparison'){. "$PSScriptRoot/../$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
$a=[pscustomobject]@{Issue=$null;Devices=@([pscustomobject]@{UUID='GPU-abcd';Current=500});ClockIssue=$null;ClockOffsets=@([pscustomobject]@{UUID='GPU-abcd';Available=$true;CoreMHz=0;MemoryMHz=0})}
$b=$a|ConvertTo-Json -Depth 8|ConvertFrom-Json;$b.ClockOffsets[0].CoreMHz=50
Assert ((Get-PCPowerSignature $a) -ne (Get-PCPowerSignature $b)) 'Changed offsets were combined into one repeated-test settings group'
$a.Issue='No power tool';$b.Issue='No power tool'
Assert ((Get-PCPowerSignature $a) -ne (Get-PCPowerSignature $b)) 'Missing power data hid clock changes'
$a.Issue=$null;$b.Issue=$null
$old=[pscustomobject]@{Issue=$null;Devices=$a.Devices}
Assert ((Get-PCPowerSignature $old) -eq 'GPU-abcd=500W') 'Legacy power context changed'
$x=[pscustomobject]@{Timestamp='a';Test='SHA256-1MiB-parallel-v2';CPUName='Mock CPU';Runtime='4';Workers=8;Completed=$true;Seconds=20;MiBPerSecond=100;PowerStateAtStart=$a;Frames=@()}
$y=$x|Select-Object *;$y.Timestamp='b';$y.PowerStateAtStart=$b
$comparison=Get-PCSessionComparison $x $y
Assert (($comparison.Notes -join ' ') -match 'core 50 MHz') 'Comparison omitted recorded clock changes'
$y.PowerStateAtStart=$old
Assert (((Get-PCSessionComparison $x $y).Notes -join ' ') -match 'B: unavailable') 'Old sessions invented clock offsets'
'PASS: clock changes separate repeated test settings and appear in saved-session comparison; legacy/missing context preserved'
