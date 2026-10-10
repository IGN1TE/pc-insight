function Initialize-PCClockNative {
    if(-not ('PCNvidiaClockNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'NvidiaClockNative.cs')}
}
function Get-PCClockDevices {Initialize-PCClockNative;[PCNvidiaClockNative]::ReadAll()}
function Get-PCClockDevice([string]$UUID){Initialize-PCClockNative;[PCNvidiaClockNative]::Read($UUID)}
function Set-PCClockOffset([string]$UUID,[uint32]$Domain,[int]$MHz){Initialize-PCClockNative;[PCNvidiaClockNative]::Write($UUID,$Domain,$MHz)}
function Test-PCClockAdministrator {([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function ConvertTo-PCClockInteger($Value) {
    $number=0
    if($null -eq $Value -or [string]$Value -notmatch '^[+-]?[0-9]+$' -or -not [int]::TryParse([string]$Value,[ref]$number)){throw 'Clock offsets must be whole MHz numbers.'}
    $number
}
function Assert-PCClockDevice($Device,[string]$UUID) {
    if(-not $Device -or -not $Device.Available -or $Device.UUID -ne $UUID -or $UUID -notmatch '^GPU-[a-fA-F0-9-]+$'){throw 'Selected GPU clock offsets are unavailable. Detect clock support again.'}
    foreach($domain in 'Core','Memory'){
        $current=ConvertTo-PCClockInteger $Device.($domain+'MHz');$min=ConvertTo-PCClockInteger $Device.($domain+'Min');$max=ConvertTo-PCClockInteger $Device.($domain+'Max')
        if($min -gt $max -or $current -lt $min -or $current -gt $max){throw 'Driver returned inconsistent clock limits.'}
    }
    if([string]::IsNullOrWhiteSpace([string]$Device.Driver)){throw 'NVIDIA driver version is unavailable.'}
}
function Assert-PCClockTargets($Device,[int]$Core,[int]$Memory) {
    if($Core -lt $Device.CoreMin -or $Core -gt $Device.CoreMax -or $Memory -lt $Device.MemoryMin -or $Memory -gt $Device.MemoryMax){throw 'Requested offsets are outside the driver-reported range. That range is not a stability guarantee.'}
}
function Assert-PCClockApplyTemperature($Device) {
    $temperature=0.0
    if($null -eq $Device.TemperatureC -or
        -not [double]::TryParse([string]$Device.TemperatureC,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$temperature) -or
        [double]::IsNaN($temperature) -or [double]::IsInfinity($temperature) -or $temperature -le 0 -or $temperature -ge 85){
        throw 'A current GPU temperature below the 85 C preview cutoff is required. This is not a guarantee of stability.'
    }
}
function Save-PCClockJournal($Journal,[string]$Path) {
    $full=[IO.Path]::GetFullPath($Path);$temporary=Join-Path ([IO.Path]::GetDirectoryName($full)) ([IO.Path]::GetRandomFileName())
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Journal|ConvertTo-Json -Depth 6))
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if([IO.File]::Exists($full)){[IO.File]::Replace($temporary,$full,[NullString]::Value)}else{[IO.File]::Move($temporary,$full)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Read-PCClockJournal([string]$Path) {
    $j=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($j.Schema -ne 1 -or $j.Kind -ne 'PCInsight.NvidiaClockOffsets' -or $j.Pstate -ne 0 -or $j.UUID -notmatch '^GPU-[a-fA-F0-9-]+$' -or $j.State -notin @('Pending','Applied','RecoveryRequired') -or [string]::IsNullOrWhiteSpace([string]$j.Driver)){throw 'Clock recovery record is invalid. No changes were made.'}
    foreach($field in 'OriginalCore','OriginalMemory','LastCore','LastMemory'){$null=ConvertTo-PCClockInteger $j.$field}
    $j
}
function Set-PCClockPairAndVerify([string]$UUID,[int]$Core,[int]$Memory,$Expected,[ref]$WriteAttempted) {
    $live=Get-PCClockDevice $UUID;Assert-PCClockDevice $live $UUID;Assert-PCClockTargets $live $Core $Memory
    if($live.Driver -ne $Expected.Driver -or $live.CoreMHz -ne $Expected.CoreMHz -or $live.MemoryMHz -ne $Expected.MemoryMHz){throw 'GPU settings changed immediately before writing. Detect clock support again.'}
    Assert-PCClockApplyTemperature $live
    if($live.CoreMHz -ne $Core){$WriteAttempted.Value=$true;Set-PCClockOffset $UUID 0 $Core}
    if($live.MemoryMHz -ne $Memory){$WriteAttempted.Value=$true;Set-PCClockOffset $UUID 2 $Memory}
    $read=Get-PCClockDevice $UUID;Assert-PCClockDevice $read $UUID
    if($read.CoreMHz -ne $Core -or $read.MemoryMHz -ne $Memory){throw "Clock readback mismatch. Requested core $Core / memory $Memory MHz; reported $($read.CoreMHz) / $($read.MemoryMHz) MHz."}
    $read
}
function Undo-PCClockPair([string]$UUID,[int]$Core,[int]$Memory) {
    # Attempt both independently so one rejected domain does not prevent recovery of the other.
    $errors=[Collections.Generic.List[string]]::new()
    foreach($pair in @(@(0,$Core),@(2,$Memory))){try{Set-PCClockOffset $UUID $pair[0] $pair[1]}catch{$errors.Add($_.Exception.Message)}}
    $read=Get-PCClockDevice $UUID;Assert-PCClockDevice $read $UUID
    if($read.CoreMHz -ne $Core -or $read.MemoryMHz -ne $Memory){throw ('Clock restore could not be verified. '+($errors -join ' '))}
    $read
}
function Set-PCGpuClockOffsets($Selected,$CoreMHz,$MemoryMHz,[string]$JournalPath) {
    if(-not (Test-PCClockAdministrator)){throw 'Reopen PC Insight as administrator to apply GPU clock offsets.'}
    $core=ConvertTo-PCClockInteger $CoreMHz;$memory=ConvertTo-PCClockInteger $MemoryMHz
    $live=Get-PCClockDevice $Selected.UUID;Assert-PCClockDevice $live $Selected.UUID;Assert-PCClockTargets $live $core $memory
    if($live.Driver -ne $Selected.Driver -or $live.CoreMHz -ne $Selected.CoreMHz -or $live.MemoryMHz -ne $Selected.MemoryMHz){throw 'GPU settings changed since detection. Detect clock support again before applying.'}
    Assert-PCClockApplyTemperature $live
    $journal=$null
    if(Test-Path -LiteralPath $JournalPath){
        $journal=Read-PCClockJournal $JournalPath
        if($journal.UUID -ne $live.UUID -or $journal.State -ne 'Applied' -or $journal.Driver -ne $live.Driver -or $journal.LastCore -ne $live.CoreMHz -or $journal.LastMemory -ne $live.MemoryMHz){throw 'Restore the saved clock offsets before applying another change. The prior settings or driver no longer match the verified state.'}
    }
    if($core -eq $live.CoreMHz -and $memory -eq $live.MemoryMHz){return 'Offsets already match; no clock changes made.'}
    if(-not $journal){$journal=[pscustomobject]@{Schema=1;Kind='PCInsight.NvidiaClockOffsets';Pstate=0;UUID=$live.UUID;Name=$live.Name;Driver=$live.Driver;OriginalCore=$live.CoreMHz;OriginalMemory=$live.MemoryMHz;LastCore=$core;LastMemory=$memory;State='Pending';Created=([datetimeoffset]::Now.ToString('o'))}}
    $journal.LastCore=$core;$journal.LastMemory=$memory;$journal.State='Pending'
    Save-PCClockJournal $journal $JournalPath
    $writeAttempted=$false
    try{
        $verified=Set-PCClockPairAndVerify $live.UUID $core $memory $live ([ref]$writeAttempted)
        $journal.State='Applied';Save-PCClockJournal $journal $JournalPath
        "Applied and read back P0 offsets: core $($verified.CoreMHz) MHz, memory $($verified.MemoryMHz) MHz. Original offsets are saved. Readback does not verify stability."
    }catch{
        $problem=$_.Exception.Message
        $recovery='No clock write was attempted. The saved recovery record remains.'
        if($writeAttempted){try{$null=Undo-PCClockPair $live.UUID $live.CoreMHz $live.MemoryMHz;$recovery='Previous offsets restored and read back.'}catch{$recovery='Recovery could not be verified. Use Restore saved clock offsets; the recovery record remains.'}}
        $journal.State='RecoveryRequired';try{Save-PCClockJournal $journal $JournalPath}catch{}
        throw "$problem $recovery"
    }
}
function Restore-PCGpuClockOffsets([string]$JournalPath) {
    if(-not (Test-PCClockAdministrator)){throw 'Reopen PC Insight as administrator to restore GPU clock offsets.'}
    $j=Read-PCClockJournal $JournalPath
    $live=Get-PCClockDevice $j.UUID;Assert-PCClockDevice $live $j.UUID
    Assert-PCClockTargets $live $j.OriginalCore $j.OriginalMemory
    # Restore is allowed with missing/hot temperature readings and a pending/failed apply.
    $verified=Undo-PCClockPair $j.UUID $j.OriginalCore $j.OriginalMemory
    Remove-Item -LiteralPath $JournalPath -ErrorAction Stop
    "Restored and read back original offsets: core $($verified.CoreMHz) MHz, memory $($verified.MemoryMHz) MHz on $($verified.Name)."
}
