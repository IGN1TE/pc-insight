# Read-only evidence from the System log. Never treats an unavailable query as zero errors.
function Read-PCReliabilityEvents([datetime]$Start,[datetime]$End,[string]$Provider,[int]$Id=0){
    $filter=@{LogName='System';ProviderName=$Provider;StartTime=$Start;EndTime=$End}
    if($Id){$filter.Id=$Id}
    try{Get-WinEvent -FilterHashtable $filter -MaxEvents 101 -ErrorAction Stop}
    catch{if($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'){throw}}
}
function Get-PCReliabilityEvidence([datetime]$Start,[datetime]$End){
    $events=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new()
    if($End -lt $Start){throw 'Reliability interval ends before it starts.'}
    foreach($source in @(@{Provider='Microsoft-Windows-WHEA-Logger';Id=0},@{Provider='Display';Id=4101})){
        try{
            $rows=@(Read-PCReliabilityEvents $Start $End $source.Provider $source.Id)
            $truncated=$rows.Count -gt 100
            foreach($row in ($rows | Select-Object -First 100)){
                # Do not copy raw messages, computer names, user IDs or hardware serials into reports.
                $events.Add([pscustomobject]@{Provider=[string]$row.ProviderName;Id=[int]$row.Id;Level=[int]$row.Level;RecordId=$row.RecordId;TimeCreated=if($row.TimeCreated){$row.TimeCreated.ToUniversalTime().ToString('o')}else{$null}})
            }
            $checks.Add([pscustomobject]@{Provider=$source.Provider;Available=$true;Count=[math]::Min(100,$rows.Count);Truncated=$truncated;Issue=$null})
        }catch{
            $checks.Add([pscustomobject]@{Provider=$source.Provider;Available=$false;Count=$null;Truncated=$false;Issue='System log query unavailable: '+$_.Exception.GetType().Name})
        }
    }
    $available=@($checks | Where-Object Available).Count -eq 2
    $truncated=@($checks | Where-Object Truncated).Count -gt 0
    $status=if($events.Count){'Events found; review required'}elseif(-not $available){'Event evidence unavailable or incomplete'}else{'No matching events found in this interval'}
    [pscustomobject]@{Schema=1;StartUtc=$Start.ToUniversalTime().ToString('o');EndUtc=$End.ToUniversalTime().ToString('o');Available=$available;Truncated=$truncated;Status=$status;Checks=@($checks.ToArray());Events=@($events.ToArray());Limitations='Post-test System log snapshot: WHEA-Logger events and Display 4101 only. Events can be delayed, cleared or disabled. Temporal overlap does not prove the test or GPU caused an event. No matching events does not establish stability.'}
}
function Format-PCReliabilityEvidence($Evidence){
    if(-not $Evidence){return 'Windows event evidence: not collected for this saved session.'}
    $lines=@('Windows event evidence: '+$Evidence.Status)
    foreach($check in $Evidence.Checks){
        if(-not $check.Available){$lines+=($check.Provider+': unavailable')}
        else{$suffix=if($check.Truncated){' (first 100 retained; more exist)'}else{''};$lines+=('{0}: {1} event(s){2}' -f $check.Provider,$check.Count,$suffix)}
    }
    foreach($event in (@($Evidence.Events) | Select-Object -First 8)){$lines+=('{0} | {1} | event {2} | record {3}' -f $event.TimeCreated,$event.Provider,$event.Id,$event.RecordId)}
    if(@($Evidence.Events).Count -gt 8){$lines+='Export the session JSON for all retained event references.'}
    $lines+=$Evidence.Limitations
    $lines -join "`n"
}
