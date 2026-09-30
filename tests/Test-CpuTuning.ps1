# Simulated CPU, sensors and workload only. No hardware-setting calls.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Power.ps1"
. "$PSScriptRoot/../Monitor.ps1"
. "$PSScriptRoot/../CpuTuning.ps1"
. "$PSScriptRoot/CpuTuning.Fixtures.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Copy-Value($v){$v|ConvertTo-Json -Depth 12|ConvertFrom-Json}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed 'Expected rejection did not occur'}
$baseline=New-CpuBaselineFixture
Assert ((Get-PCCpuBatchSummary $baseline.BeforeRuns).Median -eq 101) 'Baseline median incorrect'
$r=New-PCCpuTrial 'Retest' 'External CPU profile changed' $baseline
$r.AfterRuns=@(1..3|ForEach-Object{New-CpuRunFixture $_ (109+$_)});$r.State='Completed'
$comparison=Compare-PCCpuTrial $r
Assert ($comparison.Verdict -eq 'Higher measured throughput' -and $comparison.ChangePercent -eq 9.9) 'Matching comparison failed'
$r.BeforeRuns[0].MiBPerSecond=99
Assert ($baseline.BeforeRuns[0].MiBPerSecond -eq 100 -and $r.Id -ne $baseline.Id -and $r.ParentId -eq $baseline.Id) 'Retest mutated original baseline or reused identity'
foreach($field in 'CPU','Manufacturer','Board','BIOS','OS','Memory','Plan','Runtime','Cores','Threads'){
    $bad=Copy-Value $r
    if($field -in @('Cores','Threads')){$bad.AfterRuns[0].ContextBefore.$field=64}else{$bad.AfterRuns[0].ContextBefore.$field='changed'}
    Assert ($null -eq (Compare-PCCpuTrial $bad).ChangePercent) "Mismatched $field produced a comparison"
}
foreach($field in 'Seconds','MiBPerSecond','Workers','StartCPU','PeakCPU'){
    foreach($value in @($null,[double]::NaN,[double]::PositiveInfinity,-1,$true)){
        $bad=Copy-Value $r;$bad.AfterRuns[0].$field=$value
        Assert ($null -eq (Compare-PCCpuTrial $bad).ChangePercent) "Invalid $field produced a comparison"
    }
}
$bad=Copy-Value $r;$bad.AfterRuns[2].RunIndex=1;Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Unavailable') 'Duplicate run counted'
$bad=Copy-Value $r;$bad.AfterRuns[0].Completed=$false;Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Unavailable') 'Incomplete run counted'
$bad=Copy-Value $r;$bad.AfterRuns[0].ContextAfter.BIOS='2';Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Unavailable') 'Mid-run context drift ignored'
$bad=Copy-Value $r;$bad.AfterRuns[0].MiBPerSecond=140;Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Inconclusive') 'Noisy retest accepted'
$bad=Copy-Value $r;foreach($run in $bad.AfterRuns){$run.StartCPU=56;$run.PeakCPU=60};Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Inconclusive') 'Unequal starting temperature accepted'
$bad=Copy-Value $r;$bad.AfterRuns=@($baseline.BeforeRuns);Assert ((Compare-PCCpuTrial $bad).Verdict -eq 'Inconclusive') 'Overlapping ranges accepted'
$bad=Copy-Value $baseline;$bad.BeforeRuns[0].MiBPerSecond=150;Reject {New-PCCpuTrial 'Retest' 'Change' $bad}
Reject {New-PCCpuTrial 'Baseline' ' ' $null}
$bad=Copy-Value $baseline;$bad.State='Interrupted';Reject {New-PCCpuTrial 'Retest' 'Change' $bad}
# Persisted history and actual experiment orchestration with bounded mock workloads.
$folder=Join-Path ([IO.Path]::GetTempPath()) ('cpu-tests-'+[guid]::NewGuid().ToString('N'))
$script:contextCalls=0;$script:driftAt=0;$script:runs=0;$script:failAt=0
function Get-PCCpuTuningContext {$script:contextCalls++;$c=New-CpuContextFixture;if($script:driftAt -and $script:contextCalls -ge $script:driftAt){$c.BIOS='changed'};$c}
function Get-PCSensorFrame {[pscustomobject]@{CPUCelsius=50;QuerySeconds=0.1;Issue=$null}}
function Start-Sleep {param($Seconds,$Milliseconds)}
function Invoke-PCSensorSession {
    param([switch]$WithLoad,$DurationSeconds,[scriptblock]$Guard)
    if($Guard){& $Guard};$script:runs++
    if($script:failAt -eq $script:runs){throw 'Simulated sensor failure'}
    $v=New-CpuRunFixture 1 100
    foreach($name in 'RunIndex','ContextBefore','ContextAfter','StartCPU','TemperatureSamples'){$v.PSObject.Properties.Remove($name)}
    [pscustomobject]@{Kind='Result';Value=$v}
}
try {
    $trial=New-PCCpuTrial 'Baseline' 'Stock profile' $null
    $null=Invoke-PCCpuTrial $trial $folder {}
    Assert ($trial.State -eq 'Ready' -and $script:runs -eq 3) 'Baseline orchestration failed'
    $saved=Read-PCCpuTrial (Join-Path $folder ($trial.Id+'.json'))
    Assert ($saved.BeforeRuns.Count -eq 3 -and $saved.BeforeRuns[2].Frames.Count -eq 61) 'Per-run persistence truncated data'
    $next=New-PCCpuTrial 'Retest' 'User BIOS change' $saved
    $null=Invoke-PCCpuTrial $next $folder {}
    Assert ($next.State -eq 'Completed' -and (Compare-PCCpuTrial $next).Verdict -eq 'Inconclusive') 'Retest did not use saved baseline'
    $script:runs=0;$script:contextCalls=0;$script:driftAt=2
    $stopped=New-PCCpuTrial 'Baseline' 'Stock' $null;$null=Invoke-PCCpuTrial $stopped $folder {}
    Assert ($stopped.State -eq 'Stopped' -and $script:runs -eq 1 -and $stopped.BeforeRuns.Count -eq 1 -and $stopped.Message -match 'BIOS') 'Context drift did not checkpoint and stop'
    $script:driftAt=0;$script:runs=0;$script:failAt=2
    $failed=New-PCCpuTrial 'Baseline' 'Stock' $null;$null=Invoke-PCCpuTrial $failed $folder {}
    Assert ($failed.State -eq 'Stopped' -and $failed.BeforeRuns.Count -eq 1) 'Worker failure lost completed run'
    $script:runs=0;$script:failAt=0
    $cancel=New-PCCpuTrial 'Baseline' 'Stock' $null;$null=Invoke-PCCpuTrial $cancel $folder {throw 'Stopped by test'}
    Assert ($cancel.State -eq 'Stopped' -and $script:runs -eq 0) 'Cancellation started workload'
    $interrupted=New-PCCpuTrial 'Baseline' 'Stock' $null;Save-PCCpuTrial $interrupted $folder
    Assert ((Read-PCCpuTrial (Join-Path $folder ($interrupted.Id+'.json'))).State -eq 'Interrupted') 'Interrupted checkpoint accepted as running or complete'
    [IO.File]::WriteAllText((Join-Path $folder 'bad.json'),'{bad')
    $catalog=Get-PCCpuTrialHistory $folder
    Assert ($catalog.Entries.Count -eq 6 -and $catalog.Issues.Count -eq 1) 'Corrupt record hid valid history'
    Assert ((Format-PCCpuTrial $next) -match 'user reported' -and (Format-PCCpuTrial $next) -match 'Inconclusive') 'Report omitted note provenance or uncertainty'
}finally{Remove-Item $folder -Recurse -Force}
'PASS: CPU baseline/retest, copy isolation, context drift, invalid readings, variability, checkpoint recovery, cancellation, archive isolation and reports.'
