$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
. "$PSScriptRoot/../RepeatedTests.ps1"
. "$PSScriptRoot/../CpuResults.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function New-Runs($id,$rate,$pl1=253){
    1..3 | ForEach-Object {
        $cpu=[pscustomobject]@{Available=$true;Identity='pc1';BIOS='4505';PL1Watts=$pl1;PL2Watts=253;RawLimitHex=('{0:X16}' -f [long]$pl1);RawUnitsHex='3';Locked=$false;PL1Enabled=$true;PL2Enabled=$true}
        $state=[pscustomobject]@{CpuPower=$cpu;Devices=@()}
        [pscustomobject]@{BatchId=$id;RunIndex=$_;RunCount=3;Test='SHA256-1MiB-parallel-60s-v1';Timestamp="2026-10-01T00:00:0$_";CPUName='i7-13700K';Runtime='4';Workers=24;Plan='balanced';Completed=$true;StopReason=$null;MiBPerSecond=($rate+$_);PeakCPU=(80+$_);Seconds=60;PowerStateAtStart=$state;PowerStateAtEnd=$state}
    }
}
$left=@(New-Runs 'a' 1000);$right=@(New-Runs 'b' 990 248)
$a=@(Get-PCCpuResultBatches $left)[0];$b=@(Get-PCCpuResultBatches $right)[0]
$comparison=Get-PCCpuBatchComparison $a $b
Assert ($comparison.Comparable -and $comparison.PercentChange -lt 0 -and $a.Stats.Median -eq 1002 -and $b.PowerText -match '248.0') 'Valid power-limit comparison failed'
Assert ($a.PeakCPU -eq 83 -and $a.TemperatureRuns -eq 3) 'Temperature summary failed'
Assert (-not (Get-PCCpuBatchComparison $a $a).Comparable) 'Same batch compared against itself'
foreach($case in @('incomplete','duplicate','failed','nan','duration','workers','mixed','missingend','drift','old','identity','bios')){
    $rows=@(New-Runs 'b' 990 248)
    switch($case){
        incomplete {$rows=$rows[0..1]}
        duplicate {$rows[2].RunIndex=2}
        failed {$rows[0].Completed=$false}
        nan {$rows[0].MiBPerSecond=[double]::NaN}
        duration {$rows[0].Seconds=20}
        workers {$rows[0].Workers=0}
        mixed {$rows[0].Plan='performance'}
        missingend {$rows[0].PowerStateAtEnd=$null}
        drift {$rows[0].PowerStateAtEnd=$left[0].PowerStateAtStart}
        old {foreach($r in $rows){$r.PowerStateAtStart=[pscustomobject]@{Devices=@()};$r.PowerStateAtEnd=$r.PowerStateAtStart}}
        identity {foreach($r in $rows){$r.PowerStateAtStart.CpuPower.Identity='pc2'}}
        bios {foreach($r in $rows){$r.PowerStateAtStart.CpuPower.BIOS='new'}}
    }
    $batch=@(Get-PCCpuResultBatches $rows)[0];$c=Get-PCCpuBatchComparison $a $batch
    Assert (-not $c.Comparable -and $null -eq $c.PercentChange) "$case produced a misleading comparison"
}
$rows=@(New-Runs 'c' 1000);$rows[0].MiBPerSecond=800
$c=Get-PCCpuBatchComparison $a (@(Get-PCCpuResultBatches $rows)[0])
Assert ($c.Comparable -and $c.Status -match 'Inconclusive') 'High variance not labelled'
$rows=@(New-Runs 'c' 1000);$rows[0].PeakCPU=$null;$rows[1].PeakCPU=[double]::NaN
$batch=@(Get-PCCpuResultBatches $rows)[0]
Assert ($batch.TemperatureRuns -eq 1 -and $batch.PeakCPU -eq 83) 'Missing temperatures invented'
Assert (@(Get-PCCpuResultBatches @()).Count -eq 0) 'Empty history invented a batch'
'PASS: CPU batch integrity, finite scores, duration, settings boundaries, legacy metadata, identity/BIOS mismatch, variability and temperature coverage'
