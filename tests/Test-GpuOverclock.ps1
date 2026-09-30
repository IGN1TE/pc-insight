$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GpuOverclock.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
Initialize-PCClockNative
$abi=[PCNvmlClockOffset]::Create(2)
Assert ([Runtime.InteropServices.Marshal]::SizeOf($abi) -eq 24 -and $abi.Version -eq 16777240 -and $abi.Type -eq 2 -and $abi.Pstate -eq 0) 'NVML ABI layout/version is wrong'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-clock-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$script:journal=Join-Path $dir 'clock.json'
$script:original=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Driver='mock-1';Available=$true;CoreMHz=30;MemoryMHz=40;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
function Reset-Mock {
    $script:live=$script:original|Select-Object *
    $script:writes=[Collections.Generic.List[object]]::new();$script:admin=$true;$script:mode='normal';$script:memoryFailed=$false;$script:reads=0
    if(Test-Path $script:journal){Remove-Item $script:journal}
}
function Test-PCClockAdministrator {$script:admin}
function Get-PCClockDevice([string]$UUID){
    $script:reads++
    if($script:reads -eq 3){
        if($script:mode -eq 'prewrite-race'){$script:live.CoreMHz=60}
        if($script:mode -eq 'prewrite-hot'){$script:live.TemperatureC=85}
        if($script:mode -eq 'prewrite-missing'){$script:live.TemperatureC=$null}
    }
    if($UUID -ne $script:live.UUID){throw 'Mock GPU missing'}
    $script:live|Select-Object *
}
function Set-PCClockOffset([string]$UUID,[uint32]$Domain,[int]$MHz){
    Assert (Test-Path $script:journal) 'Hardware write happened before recovery journal existed'
    $record=Read-PCClockJournal $script:journal
    Assert ($record.OriginalCore -eq 30 -and $record.OriginalMemory -eq 40) 'Original offsets were overwritten'
    Assert ($UUID -eq $script:live.UUID) 'Wrong GPU was written'
    $script:writes.Add(@($Domain,$MHz))
    if($script:mode -eq 'partial' -and $Domain -eq 2 -and -not $script:memoryFailed){$script:memoryFailed=$true;throw 'Memory set rejected'}
    if($script:mode -eq 'recovery-fails' -and (($Domain -eq 2 -and $MHz -eq 200) -or ($Domain -eq 0 -and $MHz -eq 30))){throw 'Driver unavailable'}
    if($script:mode -eq 'mismatch' -and $Domain -eq 0 -and $MHz -eq 100){return}
    if($Domain -eq 0){$script:live.CoreMHz=$MHz}else{$script:live.MemoryMHz=$MHz}
}
try{
    Reset-Mock
    $selected=Get-PCClockDevice $script:live.UUID
    $null=Set-PCGpuClockOffsets $selected 100 200 $script:journal
    $j=Read-PCClockJournal $script:journal
    Assert ($j.State -eq 'Applied' -and $j.OriginalCore -eq 30 -and $j.OriginalMemory -eq 40 -and $script:live.CoreMHz -eq 100 -and $script:live.MemoryMHz -eq 200) 'Apply/readback/original capture failed'
    $null=Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 120 250 $script:journal
    Assert ((Read-PCClockJournal $script:journal).OriginalCore -eq 30) 'Repeated apply replaced the original'
    $script:live.TemperatureC=$null
    $null=Restore-PCGpuClockOffsets $script:journal
    Assert ($script:live.CoreMHz -eq 30 -and $script:live.MemoryMHz -eq 40 -and -not (Test-Path $script:journal)) 'Restore did not recover originals with missing temperature'
    Reset-Mock
    $null=Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 30 40 $script:journal
    Assert ($script:writes.Count -eq 0 -and -not (Test-Path $script:journal)) 'No-op performed hardware or journal writes'
    foreach($case in 'nonadmin','hot','missingtemp','range','stale','unsupported','malformed'){
        Reset-Mock;$selected=Get-PCClockDevice $script:live.UUID;$core=100
        switch($case){'nonadmin'{$script:admin=$false};'hot'{$script:live.TemperatureC=85};'missingtemp'{$script:live.TemperatureC=$null};'range'{$core=501};'stale'{$script:live.CoreMHz=60};'unsupported'{$script:live.Available=$false};'malformed'{$core='100.5'}}
        Reject {Set-PCGpuClockOffsets $selected $core 200 $script:journal} "Accepted $case"
        Assert ($script:writes.Count -eq 0) "Wrote clocks for $case"
    }
    Reset-Mock
    Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 (Join-Path $dir 'missing/clock.json')} 'Missing journal directory accepted'
    Assert ($script:writes.Count -eq 0) 'Journal failure still wrote clocks'
    foreach($failureMode in 'partial','mismatch'){
        Reset-Mock;$script:mode=$failureMode
        Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Rejected/mismatched driver write was reported successful'
        Assert ($script:live.CoreMHz -eq 30 -and $script:live.MemoryMHz -eq 40 -and (Read-PCClockJournal $script:journal).State -eq 'RecoveryRequired') 'Failed apply did not recover previous settings and retain originals'
        $count=$script:writes.Count
        Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Unresolved recovery allowed another apply'
        Assert ($script:writes.Count -eq $count) 'Blocked recovery performed hardware writes'
    }
    Reset-Mock;$script:mode='prewrite-race'
    Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Concurrent prewrite change accepted'
    Assert ($script:writes.Count -eq 0 -and $script:live.CoreMHz -eq 60) 'Prewrite conflict overwrote external settings during rollback'
    foreach($temperatureMode in @('prewrite-hot','prewrite-missing')){
        Reset-Mock;$script:mode=$temperatureMode
        Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Prewrite temperature change was ignored'
        Assert ($script:writes.Count -eq 0 -and (Read-PCClockJournal $script:journal).OriginalCore -eq 30) 'Temperature rejection wrote clocks or lost originals'
        $null=Restore-PCGpuClockOffsets $script:journal
        Assert (-not (Test-Path $script:journal)) 'Temperature guard prevented explicit recovery'
    }
    foreach($invalidTemperature in @([double]::NaN,[double]::PositiveInfinity,'not a temperature')){
        Reset-Mock;$script:live.TemperatureC=$invalidTemperature
        Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Invalid temperature allowed apply'
        Assert ($script:writes.Count -eq 0) 'Invalid temperature caused a clock write'
    }
    Reset-Mock;$script:mode='recovery-fails'
    Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal} 'Failed recovery was reported successful'
    Assert ($script:live.CoreMHz -eq 100 -and (Read-PCClockJournal $script:journal).OriginalCore -eq 30) 'Failed recovery lost the original'
    Assert (@($script:writes|Where-Object {$_[0] -eq 2 -and $_[1] -eq 40}).Count -eq 1) 'Core recovery failure prevented memory restore attempt'
    $script:mode='normal';$script:live.Driver='mock-new-driver'
    $null=Restore-PCGpuClockOffsets $script:journal
    Assert ($script:live.CoreMHz -eq 30 -and -not (Test-Path $script:journal)) 'Recovery after driver restart failed'
    Reset-Mock
    $null=Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 100 200 $script:journal
    $script:live.CoreMHz=130;$count=$script:writes.Count
    Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 150 300 $script:journal} 'External tuner changes were silently adopted'
    Assert ($script:writes.Count -eq $count) 'External change conflict performed a write'
    $j=Read-PCClockJournal $script:journal;$j.UUID='GPU-ffffffff-ffff-ffff-ffff-ffffffffffff';Save-PCClockJournal $j $script:journal
    Reject {Restore-PCGpuClockOffsets $script:journal} 'Wrong GPU recovery accepted'
    Assert (Test-Path $script:journal) 'Unavailable GPU recovery deleted the journal'
    Set-Content -LiteralPath $script:journal -Value '{"Schema":1,"Kind":"bad"}'
    Reject {Set-PCGpuClockOffsets (Get-PCClockDevice $script:live.UUID) 150 300 $script:journal} 'Corrupt recovery record accepted'
    foreach($v in @($null,'NaN','1e2','2147483648','1;echo x')){Reject {ConvertTo-PCClockInteger $v} 'Invalid offset accepted'}
    'PASS: NVML ABI, journal-before-write, original preservation, exact readback, partial failure rollback, independent recovery, stale/unsupported/admin/temp/range guards, corrupt/missing journals, driver restart and external tuner conflicts'
}finally{Remove-Item $dir -Recurse -Force}
