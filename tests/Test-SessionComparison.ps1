$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../SessionExport.ps1"
. "$PSScriptRoot/../SessionDetails.ps1"
. "$PSScriptRoot/../SessionComparison.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Run($rate,$stamp){[pscustomobject]@{
    Test='SHA256-1MiB-parallel-v2';CPUName='CPU A';Workers=8;Runtime='4.0';Plan='balanced'
    Timestamp=$stamp;Completed=$true;MiBPerSecond=$rate;Seconds=20;Frames=@()
}}
function Sensor($id,$value){[pscustomobject]@{Parent=$id;Identifier="$id/temperature/0";HardwareName=$id;Name='GPU Core';Type='Temperature';Value=$value}}
$a=Run 100 '2026-09-29T12:00:00Z';$b=Run 110 '2026-09-29T12:01:00Z'
$result=Get-PCSessionComparison $a $b
Assert ($result.ScoreComparable -and [math]::Abs($result.Rows[0].PercentChange-10) -lt 0.00001) 'Matched CPU score change incorrect'
Assert ((Get-PCSessionComparison $b $a).Rows[0].Delta -eq -10) 'Comparison direction incorrect'
Assert (-not (Get-PCSessionComparison $a $a).ScoreComparable) 'Same object compared as independent runs'
$b.CPUName='CPU B';Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Different CPU compared'
$b.CPUName='CPU A';$b.Workers=4;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Different workers compared'
$b.Workers=8;$b.Runtime=$null;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Missing metadata accepted'
$b.Runtime='4.0';$b.Completed=$false;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Incomplete score compared'
$b.Completed='True';Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Malformed completion metadata accepted'
$b.Completed=$true;$b|Add-Member StopReason 'cutoff';Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Stopped score compared'
$b.StopReason=$null
$b.Seconds=30;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Substantially different durations accepted'
$b.Seconds=20;$b.Workers=0;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'Invalid workers accepted'
$b.Workers=8
$clone=$a|Select-Object *;Assert (-not (Get-PCSessionComparison $a $clone).ScoreComparable) 'Duplicate saved record compared as independent run'
foreach($bad in @($null,0,-1,[double]::NaN,[double]::PositiveInfinity)){
    $b.MiBPerSecond=$bad;$result=Get-PCSessionComparison $a $b
    Assert (-not $result.ScoreComparable -and $null -eq $result.Rows[0].Delta) 'Invalid score produced change'
}
$b.MiBPerSecond=110;$b.Plan='performance'
Assert ((Get-PCSessionComparison $a $b).Notes -contains 'Power plan changed between these sessions.') 'Plan change omitted'
$a.Frames=@(
    [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 0),(Sensor '/gpu/0' 999),(Sensor '/gpu/1' 50))},
    [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 20),(Sensor '/gpu/1' 70))},
    [pscustomobject]@{Sensors=@((Sensor '/gpu/0' 999));Issue='unavailable'}
)
$b.Frames=@([pscustomobject]@{Sensors=@((Sensor '/gpu/0' 30),(Sensor '/gpu/2' 90))})
$result=Get-PCSessionComparison $a $b
$matched=@($result.Rows|Where-Object Metric -eq '/gpu/0 / GPU Core (Temperature) - mean')[0]
Assert ($matched.Before -eq 10 -and $matched.After -eq 30 -and $matched.Delta -eq 20) 'Duplicate/bad frames or zero lost in sensor comparison'
Assert ($matched.Coverage -eq 'A 2/3 (67%) | B 1/1 (100%)') 'Coverage omitted'
$missing=@($result.Rows|Where-Object Metric -eq '/gpu/1 / GPU Core (Temperature) - mean')[0]
Assert ($null -eq $missing.After -and $null -eq $missing.Delta) 'Missing GPU merged or coerced to zero'
Assert (@($result.Rows|Where-Object Metric -like '*GPU Core*').Count -eq 6) 'Sensor union lost a device'
Assert ($null -eq (New-PCComparisonRow 'zero' 0 10 'W').PercentChange) 'Zero baseline divided'
$b.Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';$b|Add-Member GpuFramesPerSecond 60
$result=Get-PCSessionComparison $a $b
Assert (-not $result.ScoreComparable -and $result.Rows[0].BeforeText -like '*MiB/s' -and $result.Rows[0].AfterText -like '*draws/s') 'Different benchmark units mislabeled'
$a.Test=$b.Test;$a|Add-Member GpuFramesPerSecond 50
foreach($s in @($a,$b)){$s|Add-Member Renderer 'GPU A';$s|Add-Member DriverVersion '1';$s|Add-Member WarmupSeconds 5}
Assert ((Get-PCSessionComparison $a $b).ScoreComparable) 'Valid GPU comparison blocked'
$b.DriverVersion='2';Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'GPU driver mismatch accepted'
$a=Run 100 'a';$b=Run 90 'b'
foreach($s in @($a,$b)){$s.Test='RAM-copy-128MiB-20s-v1';$s|Add-Member MemoryConfig '16GB:3200';$s|Add-Member BufferMiB 128}
Assert ((Get-PCSessionComparison $a $b).ScoreComparable) 'Valid RAM comparison blocked'
$b.BufferMiB=256;Assert (-not (Get-PCSessionComparison $a $b).ScoreComparable) 'RAM buffer mismatch accepted'
$result=Get-PCSessionComparison $a $b
$copy=$result|ConvertTo-Json -Depth 12|ConvertFrom-Json
Assert ($copy.Rows.Count -eq $result.Rows.Count -and $copy.Before.Test -eq $a.Test -and $copy.Reasons.Count -gt 0) 'Export round-trip lost evidence'
Assert ($null -eq (Get-PCSessionComparison $null $b)) 'No-session handling failed'
'PASS: session comparison direction, compatibility, incomplete/malformed scores, separate sensor identities, missing/zero readings, coverage, metadata and export'
