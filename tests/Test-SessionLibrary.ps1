$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Power.ps1"
. "$PSScriptRoot/../SessionLibrary.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
$sessions=@(1..35 | ForEach-Object {[pscustomobject]@{Timestamp=('{0:D3}' -f $_);Test='SHA256-v1';CPUName='Example CPU';Completed=$true;Frames=@([pscustomobject]@{CPU=50});Pinned=($_ -eq 1);Note=''}})
$kept=@(Get-PCRetainedSessions $sessions)
Assert ($kept.Count -eq 31 -and $kept[0].Timestamp -eq '001' -and $kept[1].Timestamp -eq '006' -and $kept[-1].Timestamp -eq '035') 'Pinned result lost or recent retention incorrect'
$updated=@(Set-PCSessionAnnotation $sessions '002|SHA256-v1' $true '  Original settings  ')
Assert ($updated[1].Pinned -eq $true -and $updated[1].Note -eq 'Original settings' -and -not $sessions[1].Pinned -and -not $sessions[1].Note) 'Annotations mutated original data before save'
Assert ($updated[1].Frames[0].CPU -eq 50) 'Annotations changed readings'
$items=@(Get-PCSessionLibraryItems $updated 'CPU' 'original SETTINGS' $true)
Assert ($items.Count -eq 1 -and $items[0].Key -eq '002|SHA256-v1') 'Search/category/pinned intersection failed'
Assert (@(Get-PCSessionLibraryItems $updated 'GPU').Count -eq 0) 'Category filter failed'
Assert (@(Get-PCSessionLibraryItems $updated 'All' '*').Count -eq 0) 'Search incorrectly interpreted wildcard'
$legacy=[pscustomobject]@{Test='Sensors-only-v1';Timestamp='old'}
Assert ((Get-PCSessionLibraryItems @($legacy))[0].Label -match 'Recorded') 'Legacy data falsely marked completed'
foreach($pair in @(@('GPU-endurance-300s-v1','GPU'),@('OpenGL-test','GPU'),@('RAM-copy','RAM'),@('Continuous-monitor-v1','Monitoring'),@('unknown','Other'))){Assert ((Get-PCSessionCategory ([pscustomobject]@{Test=$pair[0]})) -eq $pair[1]) 'Incorrect test category'}
$many=@(1..21|ForEach-Object{[pscustomobject]@{Timestamp="$_";Test='test';Pinned=($_ -lt 21)}})
$rejected=$false;try{$null=Set-PCSessionAnnotation $many '21|test' $true ''}catch{$rejected=$true};Assert $rejected 'Pin limit bypassed'
Assert (@(Set-PCSessionAnnotation $many '1|test' $true 'Still editable').Count -eq 21) 'Existing pin cannot be edited at cap'
$rejected=$false;try{$null=Set-PCSessionAnnotation $sessions 'missing' $false ''}catch{$rejected=$true};Assert $rejected 'Missing selection accepted'
$rejected=$false;try{$null=Set-PCSessionAnnotation $sessions '001|SHA256-v1' $false ('x'*241)}catch{$rejected=$true};Assert $rejected 'Oversized note accepted'
$path=Join-Path ([IO.Path]::GetTempPath()) ('pc-library-'+[guid]::NewGuid()+'.json')
try{
    Save-PCSessionLibrary $updated $path
    $read=@(Expand-PCHistory (Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json))
    Assert ($read.Count -eq 35 -and $read[1].Note -eq 'Original settings' -and $read[1].Pinned) 'Saved annotations did not round-trip'
    $bytes=[IO.File]::ReadAllBytes($path)
    $rejected=$false;try{Save-PCSessionLibrary @() $path $true}catch{$rejected=$true}
    Assert ($rejected -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -eq [Convert]::ToBase64String($bytes)) 'Unreadable-history guard overwrote file'
}finally{if(Test-Path $path){Remove-Item $path}}
'PASS: pinned/recent retention, immutable notes, literal search, categories, legacy states, limits, JSON persistence and unreadable-history preservation'
