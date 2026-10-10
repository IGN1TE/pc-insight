$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Reliability.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
$start=[datetime]'2026-10-10T10:00:00Z';$end=$start.AddMinutes(5)
function Read-PCReliabilityEvents($Start,$End,$Provider,$Id){
    Assert ($Start -eq $script:start -and $End -eq $script:end) 'Query interval drifted'
    if($script:mode -eq 'denied' -and $Provider -eq 'Display'){throw [UnauthorizedAccessException]::new('private detail')}
    if($script:mode -in 'events','many' -and $Provider -eq 'Microsoft-Windows-WHEA-Logger'){
        $n=if($script:mode -eq 'many'){101}else{1}
        1..$n | ForEach-Object {[pscustomobject]@{ProviderName=$Provider;Id=19;Level=3;RecordId=$_;TimeCreated=$Start;Message='private raw message';MachineName='private-pc'}}
    }
}
$script:mode='empty';$r=Get-PCReliabilityEvidence $start $end
Assert ($r.Available -and $r.Events.Count -eq 0 -and $r.Status -match 'No matching') 'Empty successful query misclassified'
$script:mode='denied';$r=Get-PCReliabilityEvidence $start $end
Assert (-not $r.Available -and $r.Checks[1].Count -eq $null -and $r.Status -match 'unavailable') 'Access failure invented a zero count'
Assert (($r|ConvertTo-Json -Depth 8) -notmatch 'private detail') 'Exception disclosed private details'
$script:mode='events';$r=Get-PCReliabilityEvidence $start $end
Assert ($r.Events.Count -eq 1 -and $r.Status -match 'review required' -and (Format-PCReliabilityEvidence $r) -match 'event 19') 'Event not surfaced'
Assert (($r|ConvertTo-Json -Depth 8) -notmatch 'private raw|private-pc') 'Raw event data leaked'
$script:mode='many';$r=Get-PCReliabilityEvidence $start $end
Assert ($r.Truncated -and $r.Events.Count -eq 100 -and (Format-PCReliabilityEvidence $r) -match 'more exist') 'Truncated evidence misrepresented'
Assert ((Format-PCReliabilityEvidence $null) -match 'not collected') 'Legacy record claimed success'
$blocked=$false;try{Get-PCReliabilityEvidence $end $start}catch{$blocked=$true};Assert $blocked 'Reversed interval accepted'
# Exercise production query's error semantics separately from evidence conversion.
. "$PSScriptRoot/../Reliability.ps1"
function Get-WinEvent {param($FilterHashtable,$MaxEvents,$ErrorAction)
    Assert ($MaxEvents -eq 101 -and $FilterHashtable.LogName -eq 'System' -and $FilterHashtable.Id -eq 4101) 'Query bounds/filter missing'
    $record=[Management.Automation.ErrorRecord]::new([Exception]::new('fixture'),$script:errorId,[Management.Automation.ErrorCategory]::ObjectNotFound,$null)
    throw $record
}
$script:errorId='NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand'
Assert (@(Read-PCReliabilityEvents $start $end Display 4101).Count -eq 0) 'No-match query must be empty'
$script:errorId='AccessDenied';$blocked=$false;try{Read-PCReliabilityEvents $start $end Display 4101}catch{$blocked=$true};Assert $blocked 'Unexpected query error was suppressed'
'PASS: time bounds, empty logs, access failures, event evidence, truncation, privacy, legacy sessions and query error semantics'
