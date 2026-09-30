$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Tuning.ps1"
. "$PSScriptRoot/../CpuPowerMetadata.ps1"
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
$script:mode='ok';$script:reads=0
function Get-PCCpuPowerHardware {
    $script:reads++
    if($script:mode -eq 'throw'){throw 'No driver available'}
    $row=[pscustomobject]@{Name='i7-13700K';Identity='exact-identity';ProcessorId='cpu';BIOS='4505';BootId='boot';Supported=$true;Reason=$null;RawLimitHex='0000806400008064';RawUnitsHex='0000000000000003';PL1Watts=125.0;PL2Watts=253.0;Locked=$false;PL1Enabled=$true;PL2Enabled=$true}
    switch($script:mode){
        unsupported {$row.Supported=$false;$row.RawLimitHex=$null;$row.Reason='Unsupported CPU'}
        locked {$row.Supported=$false;$row.Locked=$true;$row.Reason='Power register locked'}
        disabled {$row.Supported=$false;$row.PL1Enabled=$false;$row.PL1Watts=0;$row.Reason='PL1 disabled'}
        nan {$row.PL1Watts=[double]::NaN}
        missing {$row.Identity=$null}
        raw {$row.RawLimitHex='not-hex'}
        bool {$row.Locked='false'}
    }
    $row
}
function Get-PCPowerDevices {[pscustomobject]@{UUID='GPU-abcd';Current=400}}
function Get-PCClockDevices {[pscustomobject]@{UUID='GPU-abcd';Available=$true;CoreMHz=0;MemoryMHz=0}}
function Set-PCCpuPowerHardware {throw 'Metadata must never write hardware'}
$read=Get-PCCpuPowerTestContext
Assert ($read.Available -and $read.PL1Watts -eq 125 -and $read.PL2Watts -eq 253 -and $read.BIOS -eq '4505' -and $read.BootId -eq 'boot') 'Read metadata missing'
Assert ((Test-PCRecordedCpuPower $read) -and $script:reads -eq 1) 'Unexpected repeated read or invalid context'
foreach($mode in @('unsupported','throw','nan','missing','raw','bool')){
    $script:mode=$mode;$state=Get-PCTuningCapabilities
    Assert (-not $state.CpuPower.Available -and $state.CpuPower.Reason -and $state.Devices[0].Current -eq 400 -and $state.ClockOffsets[0].Available) "CPU $mode must not break GPU tests"
}
foreach($mode in @('locked','disabled')){
    $script:mode=$mode;$state=Get-PCTuningCapabilities
    Assert ($state.CpuPower.Available -and -not $state.CpuPower.Supported) 'Read availability must not require write support'
}
$script:mode='ok';$state=Get-PCTuningCapabilities
Assert ($state.CpuPower.Available -and $state.CpuPower.RawLimitHex -eq '0000806400008064' -and $state.CpuPower.RawUnitsHex -eq '0000000000000003') 'Capabilities dropped complete raw CPU context'
Assert ((Get-PCRecordedCpuPowerContext $state) -match 'PL1 125.0 W.*PL2 253.0 W') 'Human power context missing'
Assert ((Get-PCRecordedCpuPowerContext $null) -eq 'CPU limits unavailable') 'Missing metadata treated as known'
function CpuRows($batch,$rate){1..3|ForEach-Object{[pscustomobject]@{
    BatchId=$batch;RunIndex=$_;Test='SHA256-1MiB-parallel-60s-v1';Timestamp="2026-01-0$batch`T00:00:0$_";CPUName='CPU';Runtime='4';Workers=8;Plan='A';Completed=$true;StopReason=$null;MiBPerSecond=$rate
    PowerStateAtStart=[pscustomobject]@{Devices=@([pscustomobject]@{UUID='GPU-abcd';Current=400})}
}}}
$old=@(CpuRows 1 100);$new=@(CpuRows 3 110)
$baseline=[pscustomobject]@{Created='2026-01-02';Benchmarks=$old;Sessions=@()}
$report=Get-PCBaselineComparison $baseline $new @()
Assert ($report -match 'CPU limits unavailable for at least one batch' -and $report -notmatch 'HIGHER MEASURED THROUGHPUT') 'Missing CPU limits must not produce a controlled CPU tuning conclusion'
'PASS: read-only CPU metadata, complete hardware context, unsupported/failed reads preserve GPU tests, human display and incomplete CPU baseline coverage'
