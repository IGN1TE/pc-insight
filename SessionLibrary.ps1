# Saved-data operations only. Pinned sessions are additional to the rolling history.
function Get-PCSessionKey($Session) {
    if($null -eq $Session){return ''}
    [string]$Session.Timestamp+'|'+[string]$Session.Test
}
function Get-PCSessionCategory($Session) {
    switch -Wildcard ([string]$Session.Test) {
        'SHA256*' {'CPU';break}
        'OpenGL*' {'GPU';break}
        'GPU-endurance*' {'GPU';break}
        'RAM-*' {'RAM';break}
        'Sensors-*' {'Monitoring';break}
        'Continuous-monitor*' {'Monitoring';break}
        default {'Other'}
    }
}
function Get-PCRetainedSessions($Sessions) {
    # Preserve pinned data, including legacy files containing more than the UI limit.
    $pinned=@($Sessions | Where-Object {$null -ne $_ -and $_.Pinned -eq $true})
    $recent=@($Sessions | Where-Object {$null -ne $_ -and $_.Pinned -ne $true} | Select-Object -Last 30)
    @(@($pinned)+@($recent) | Sort-Object Timestamp)
}
function Get-PCSessionLibraryItems($Sessions,[string]$Category='All',[string]$Search='', [bool]$PinnedOnly=$false) {
    $query=$Search.Trim()
    @($Sessions | Where-Object {
        $null -ne $_ -and (-not $PinnedOnly -or $_.Pinned -eq $true) -and
        ($Category -eq 'All' -or (Get-PCSessionCategory $_) -eq $Category) -and
        (-not $query -or (([string]$_.Timestamp+' '+[string]$_.Test+' '+[string]$_.CPUName+' '+[string]$_.GPUName+' '+[string]$_.Note).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0))
    } | Sort-Object Timestamp -Descending | ForEach-Object {
        $state=if($_.StopReason -or $_.Completed -eq $false){'Stopped'}elseif($_.Completed -eq $true){'Completed'}else{'Recorded'}
        $prefix=if($_.Pinned -eq $true){'[Pinned] '}else{''}
        $note=if($_.Note){' | '+[string]$_.Note}else{''}
        [pscustomobject]@{Key=(Get-PCSessionKey $_);Label=($prefix+[string]$_.Timestamp+' | '+[string]$_.Test+' | '+$state+$note);Session=$_}
    })
}
function Set-PCSessionAnnotation($Sessions,[string]$Key,[bool]$Pinned,[string]$Note) {
    if($Note.Length -gt 240){throw 'Notes can contain at most 240 characters.'}
    $matches=@($Sessions | Where-Object {(Get-PCSessionKey $_) -eq $Key})
    if($matches.Count -ne 1){throw 'The selected session is missing or ambiguous. Refresh the result list.'}
    if($Pinned -and $matches[0].Pinned -ne $true -and @($Sessions | Where-Object {$_.Pinned -eq $true}).Count -ge 20){throw 'Twenty sessions are already pinned. Unpin one before pinning another.'}
    @($Sessions | ForEach-Object {
        if((Get-PCSessionKey $_) -eq $Key){
            $copy=$_ | Select-Object *
            $copy | Add-Member -NotePropertyName Pinned -NotePropertyValue $Pinned -Force
            $copy | Add-Member -NotePropertyName Note -NotePropertyValue ($Note.Trim()) -Force
            $copy
        }else{$_}
    })
}
function Save-PCSessionLibrary($Sessions,[string]$Path,[bool]$ReadFailed=$false) {
    if($ReadFailed){throw 'The existing session file could not be read. It has been preserved; export new results before closing, and inspect the data folder.'}
    Save-JsonAtomic @($Sessions) $Path
}
