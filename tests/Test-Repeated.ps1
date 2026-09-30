$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
function Assert($ok,$msg){if(-not $ok){throw $msg}}
function Row($batch,$i,$rate){[pscustomobject]@{BatchId=$batch;RunIndex=$i;RunCount=3;Test='RAM-copy-128MiB-20s-v1';Timestamp="2026-01-0$batch`T00:00:0$i";Completed=$true;StopReason=$null;MiBPerSecond=$rate;CPUName='CPU';Runtime='4';Workers=1;MemoryConfig='RAM';Plan='A';PowerStateAtStart=$null}}
$a=@((Row 1 1 100),(Row 1 2 102),(Row 1 3 101));$b=@((Row 2 1 95),(Row 2 2 101),(Row 2 3 98))
$stats=Get-PCGroupStats $a
Assert ($stats.Median -eq 101 -and $stats.Count -eq 3) 'Median incorrect'
Assert ((Get-PCBatchReport ($a+$b)) -match 'ranges overlap') 'Overlap note missing'
Assert ((Get-PCBatchReport @($a[0],$a[1])) -match 'Incomplete') 'Partial batch must be labelled'
$b[1].Plan='B'
Assert ((Get-PCBatchReport $b) -notmatch '3/3 matching') 'Mixed settings must be separated'
$script:count=0;$script:failOn=0
function Get-PCTuningCapabilities { [pscustomobject]@{Devices=@();Issue=$null} }
function Get-ActivePlan {'A'}
function Get-PCSensorFrame { [pscustomobject]@{Timestamp='2026-01-01';Sensors=@()} }
function Start-Sleep {param($Seconds,$Milliseconds)}
function Invoke-PCExtendedTest($kind){
 $script:count++
 if($script:count -eq $script:failOn){throw 'simulated failure'}
 [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{Test='RAM-copy-128MiB-20s-v1';Timestamp='2026-01-01';Completed=$true;StopReason=$null;MiBPerSecond=100;Frames=@()}}
}
$out=@(Invoke-PCRepeatedTest memory);$runs=$out[-1].Value.BatchResults
Assert ($runs.Count -eq 3 -and $runs[2].RunIndex -eq 3 -and $script:count -eq 3) 'Batch orchestration failed'
$script:count=0;$script:failOn=2
$out=@(Invoke-PCRepeatedTest memory);$runs=$out[-1].Value.BatchResults
Assert ($runs.Count -eq 2 -and -not $runs[1].Completed -and $script:count -eq 2) 'Failure must stop batch and preserve diagnostic'
function CpuState($raw='0000806400008064',$available=$true,$identity='cpu-a'){
    [pscustomobject]@{Devices=@();Issue=$null;CpuPower=[pscustomobject]@{Available=$available;Identity=$identity;RawLimitHex=$raw;RawUnitsHex='0000000000000003';PL1Watts=12.5;PL2Watts=12.5;PL1Enabled=$true;PL2Enabled=$true;Locked=$false;Reason=$(if($available){$null}else{'reader failed'})}}
}
$before=CpuState;$after=CpuState '0000806400008060'
Assert ((Get-PCPowerSignature $before) -ne (Get-PCPowerSignature $after)) 'CPU raw-limit change must alter signature'
$after=CpuState;$after.CpuPower.RawUnitsHex='0000000000000004'
Assert ((Get-PCPowerSignature $before) -ne (Get-PCPowerSignature $after)) 'CPU units change must alter signature'
Assert ((Get-PCPowerSignature $before) -ne (Get-PCPowerSignature (CpuState -identity 'cpu-b'))) 'CPU identity change must alter signature'
$after=CpuState;$after.CpuPower.RawLimitHex='0x806400008064';$after.CpuPower.RawUnitsHex='0x3'
Assert ((Get-PCPowerSignature $before) -eq (Get-PCPowerSignature $after)) 'Equivalent raw hex formatting split settings'
Assert ((Get-PCRecordedCpuPowerContext $before) -match 'PL1 12.5 W' -and (Get-PCRecordedCpuPowerContext $null) -eq 'CPU limits unavailable') 'CPU human context invented old settings or omitted watts'
$initial=Row 1 1 100;$initial.PSObject.Properties.Remove('PowerStateAtStart');$initial|Add-Member GpuFramesPerSecond 20
$completed=Complete-PCPowerContext $initial $before (CpuState -available $false)
Assert (-not $completed.Completed -and $null -eq $completed.MiBPerSecond -and $null -eq $completed.GpuFramesPerSecond) 'Loss of CPU reading must exclude both score kinds'
Assert ($completed.PowerStateAtStart.CpuPower.Available -and -not $completed.PowerStateAtEnd.CpuPower.Available) 'Start/end context not retained'
$initial=Row 1 1 100;$initial.PSObject.Properties.Remove('PowerStateAtStart');$initial.StopReason='Sensor cutoff.'
$completed=Complete-PCPowerContext $initial $before (CpuState '0000806400008060')
Assert ($completed.StopReason -like 'Sensor cutoff.*') 'Existing stop diagnostic lost'
$initial=Row 1 1 100;$initial.PSObject.Properties.Remove('PowerStateAtStart')
$completed=Complete-PCPowerContext $initial (CpuState -available $false) (CpuState -available $false)
Assert ($completed.Completed -and $completed.MiBPerSecond -eq 100) 'Consistently unavailable CPU metadata must not disable unsupported-device tests'
$initial=[pscustomobject]@{MiBPerSecond=100}
$completed=Complete-PCPowerContext $initial $before (CpuState '0000806400008060')
Assert ($completed.Completed -eq $false -and $completed.StopReason) 'Helper must support legacy results without completion metadata'
$mix=@((Row 3 1 100),(Row 3 2 101),(Row 3 3 102));foreach($row in $mix){$row.PowerStateAtStart=CpuState};$mix[1].PowerStateAtStart=CpuState '0000806400008060'
Assert ((Get-PCBatchReport $mix) -notmatch '3/3 matching') 'Mixed CPU register settings must not form a complete batch'
Assert ((Get-PCBatchReport $a) -match 'CPU limits unavailable') 'Legacy report must disclose missing CPU limits'
$script:count=0;$script:failOn=0;$script:readCount=0;$script:loseCpu=$false
function Get-PCTuningCapabilities {
    $script:readCount++
    if($script:readCount -eq 1){return (CpuState)}
    if($script:loseCpu){return (CpuState -available $false)}
    CpuState '0000806400008060'
}
foreach($lost in @($false,$true)){
    $script:count=0;$script:readCount=0;$script:loseCpu=$lost
    $out=@(Invoke-PCRepeatedTest memory);$runs=$out[-1].Value.BatchResults
    Assert ($runs.Count -eq 1 -and $script:count -eq 1 -and -not $runs[0].Completed -and $null -eq $runs[0].MiBPerSecond) 'Actual repeated-test path failed to exclude a CPU setting change or lost reading'
    Assert ($runs[0].PowerStateAtEnd -and $runs[0].StopReason -match 'Score excluded') 'Repeated diagnostic or end metadata lost'
}
'PASS: repeated tests, CPU register and identity grouping, state-change/lost-read score exclusion, preserved diagnostics, start/end metadata and legacy unavailable disclosure'
