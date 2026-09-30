# All native writes and workload execution are mocked. Real journal/recovery logic runs.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GpuOverclock.ps1"
. "$PSScriptRoot/../GpuClockTrial.ps1"
. "$PSScriptRoot/../Tuning.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$Action,$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-clock-trial-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$script:trialJournal=Join-Path $dir 'restore.json';$reportPath=Join-Path $dir 'trial.json';$stop=Join-Path $dir 'stop.signal'
$script:original=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Driver='mock-1';Available=$true;CoreMHz=30;MemoryMHz=40;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
$script:realSave=${function:Save-PCClockJournal}
function Reset-Mock([string]$Mode='normal'){
    $script:mode=$Mode;$script:live=$script:original|Select-Object *;$script:writes=[Collections.Generic.List[object]]::new()
    $script:runs=0;$script:saveFailed=$false;$script:memoryFailed=$false;$script:cooldowns=0
    $script:baselineRuns=1;$script:rates=@();$script:plan='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';$script:watts=450
    Get-ChildItem $dir -File|Remove-Item
}
function Test-PCClockAdministrator {$script:mode -ne 'nonadmin'}
function Get-ActivePlan {$script:plan}
function Get-PCPowerDevices {
    [pscustomobject]@{UUID=$script:live.UUID;Name=$script:live.Name;Driver=$script:live.Driver;Current=$script:watts;Min=100;Max=600;Available=($script:mode -ne 'power-unavailable')}
}
function Get-PCClockDevice($UUID){Assert ($UUID -eq $script:live.UUID) 'Wrong UUID read';$script:live|Select-Object *}
function Get-PCClockDevices {$script:live|Select-Object *;if($script:mode -eq 'multiple'){$script:live|Select-Object *}}
function Set-PCClockOffset($UUID,$Domain,$MHz){
    Assert (Test-Path $script:trialJournal) 'Write before recovery journal'
    Assert ($UUID -eq $script:live.UUID) 'Wrong UUID written'
    $j=Read-PCClockJournal $script:trialJournal;Assert ($j.OriginalCore -eq 30 -and $j.OriginalMemory -eq 40) 'Lost original values'
    $script:writes.Add(@($Domain,$MHz))
    if($script:mode -eq 'partial' -and $Domain -eq 2 -and $MHz -eq 200 -and -not $script:memoryFailed){$script:memoryFailed=$true;throw 'Memory write rejected'}
    if($script:mode -eq 'restore-fails' -and $Domain -eq 0 -and $MHz -eq 30){throw 'Core restore rejected'}
    if($Domain -eq 0){$script:live.CoreMHz=$MHz}else{$script:live.MemoryMHz=$MHz}
    if($script:mode -eq 'cancel-apply' -and $Domain -eq 2 -and $MHz -eq 200){Set-Content $stop 'stop'}
}
function Save-PCClockJournal($Journal,[string]$Path){
    if($script:mode -eq 'report-fails' -and $Journal.Stage -eq 'Retest' -and -not $script:saveFailed){$script:saveFailed=$true;throw 'Report disk error'}
    & $script:realSave $Journal $Path
}
function Wait-PCClockTrialCooldown($Expected,$StopPath,$OwnerId,$OwnerStart){
    $script:cooldowns++
    if($script:mode -eq 'cancel-cooldown' -and $script:cooldowns -eq 3){Set-Content $stop 'stop'}
    if($script:mode -eq 'warm-start' -and $script:cooldowns -eq 3){$script:live.TemperatureC=60}
    if($script:mode -eq 'power-before-apply' -and $script:cooldowns -eq 3){$script:watts=400}
    Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
    Assert-PCClockTrialState $Expected
}
function Invoke-PCClockTrialMeasurement($Expected,$StopPath,$OwnerId,$OwnerStart){
    $script:runs++
    Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
    Assert-PCClockTrialState $Expected
    if($script:runs -le $script:baselineRuns){
        Assert ($script:writes.Count -eq 0) 'Baseline was measured after a clock write'
        if($script:mode -eq 'cancel-baseline'){Set-Content $stop 'stop';Assert-PCClockTrialRunning $stop}
        if($script:mode -eq 'baseline-stale'){$script:live.CoreMHz=31}
    }else{
        Assert ($script:live.CoreMHz -eq 100 -and $script:live.MemoryMHz -eq 200) 'Retest started at wrong offsets'
        if($script:mode -eq 'retest-throws'){throw 'Driver reset during retest'}
        if($script:mode -eq 'hot'){$script:live.TemperatureC=85;Assert-PCClockTrialState $Expected}
        if($script:mode -eq 'missing-temperature'){$script:live.TemperatureC=$null;Assert-PCClockTrialState $Expected}
        if($script:mode -eq 'external-change'){$script:live.CoreMHz=110;Assert-PCClockTrialState $Expected}
        if($script:mode -eq 'cancel-retest'){Set-Content $stop 'stop';Assert-PCClockTrialRunning $stop}
    }
    $name=if($script:mode -eq 'wrong-gpu'){'Different GPU'}else{'Mock GPU'}
    $rate=if($script:runs -le $script:baselineRuns){100}else{110}
    if($script:rates.Count){$rate=$script:rates[$script:runs-1]}
    if($script:mode -eq 'invalid-score' -and $script:runs -eq 2){$rate=[double]::NaN}
    if($script:mode -eq 'power-lost' -and $script:runs -eq 4){$script:watts=[double]::NaN}
    if($script:mode -eq 'power-change' -and $script:runs -eq 4){$script:watts=400}
    if($script:mode -eq 'plan-change' -and $script:runs -eq 2){$script:plan='11111111-2222-3333-4444-555555555555'}
    if($script:mode -eq 'cancel-late' -and $script:runs -eq 5){Set-Content $stop 'stop';Assert-PCClockTrialRunning $stop}
    $renderer=if($script:mode -eq 'baseline-mismatch' -and $script:runs -eq 2){'Mock GPU different renderer'}elseif($script:mode -eq 'incompatible' -and $script:runs -eq 2){'Mock GPU different renderer'}else{'Mock GPU/PCIe'}
    [pscustomobject]@{Kind='Progress';Value=50}
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{
        Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';Timestamp=[datetimeoffset]::Now.ToString('o');Seconds=30;Runtime='4.0';Renderer=$renderer;GPUName=$name;WarmupSeconds=5
        Completed=($script:mode -ne 'incomplete');StopReason=$(if($script:mode -eq 'incomplete'){'GPU stopped'}else{$null});GpuFramesPerSecond=$rate
        Frames=@([pscustomobject]@{Timestamp='2026-01-01T12:00:00Z';QuerySeconds=0.1;Issue=$null;Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Identifier='/gpu/temperature/0';Type='Temperature';Name='GPU Core';HardwareName=$name;Value=65})})
    }}
}
function Run-Trial([int]$Count=1) {
    $script:baselineRuns=$Count
    $events=@(Invoke-PCGpuClockTrial ($script:original|Select-Object *) 100 200 $script:trialJournal $reportPath $stop -RunCount $Count)
    $results=@($events|Where-Object Kind -eq 'TrialResult')
    Assert ($results.Count -eq 1) 'Trial did not emit exactly one final result'
    $results[0].Value
}
try{
    Reset-Mock
    $r=Run-Trial
    Assert ($r.State -eq 'Completed' -and $r.Restoration -eq 'Verified' -and $r.ChangePercent -eq 10) "Successful comparison/restoration failed: $($r|ConvertTo-Json -Depth 10 -Compress)"
    Assert ($script:runs -eq 2 -and $script:live.CoreMHz -eq 30 -and $script:live.MemoryMHz -eq 40 -and -not (Test-Path $script:trialJournal)) 'Successful trial left offsets applied'
    Assert ($r.BeforeRuns[0].PeakGpuC -eq 65 -and $r.BeforeRuns[0].TemperatureSamples -eq 1) 'Temperature summary missing'
    Assert ((Get-Content $reportPath -Raw|ConvertFrom-Json).Restoration -eq 'Verified') 'Saved report missed restoration'
    $recorded=Get-Content $reportPath -Raw|ConvertFrom-Json
    Assert ($recorded.BeforeRuns[0].Telemetry.Samples[0].Values[0] -eq 65 -and $recorded.AfterRuns[0].Telemetry.Channels[0].Type -eq 'Temperature') 'Trial checkpoint lost recorded sensor readings'
    Assert ((Format-PCClockTrialReport $r) -match '\+10.00%' ) 'Readable results missing change'
    foreach($mode in 'cancel-baseline','baseline-stale','wrong-gpu','incomplete'){
        Reset-Mock $mode;$r=Run-Trial
        Assert ($r.State -eq 'Stopped' -and $script:writes.Count -eq 0 -and $null -eq $r.ChangePercent) "Invalid baseline wrote clocks: $mode"
    }
    foreach($mode in 'partial','cancel-apply','retest-throws','hot','missing-temperature','external-change','cancel-retest','invalid-score','incompatible','report-fails'){
        Reset-Mock $mode;$r=Run-Trial
        Assert ($r.State -eq 'Stopped' -and $r.Restoration -eq 'Verified' -and $null -eq $r.ChangePercent) "Failed trial claimed success or missed recovery: $mode"
        Assert ($script:live.CoreMHz -eq 30 -and $script:live.MemoryMHz -eq 40 -and -not (Test-Path $script:trialJournal)) "Recovery left clocks changed: $mode"
    }
    Reset-Mock 'restore-fails';$r=Run-Trial
    Assert ($r.State -eq 'RecoveryRequired' -and $r.Restoration -eq 'RecoveryRequired' -and $null -eq $r.ChangePercent -and (Test-Path $script:trialJournal)) 'Failed restore lost recovery or advertised success'
    Assert ($script:live.MemoryMHz -eq 40) 'Failed core restore skipped memory restore'
    $script:mode='normal';$null=Restore-PCGpuClockOffsets $script:trialJournal
    Assert ($script:live.CoreMHz -eq 30 -and -not (Test-Path $script:trialJournal)) 'Explicit later recovery failed'
    foreach($mode in 'nonadmin','multiple','power-unavailable'){
        Reset-Mock $mode;Reject {Run-Trial} "Preflight accepted $mode";Assert ($script:writes.Count -eq 0) 'Preflight performed a write'
    }
    Reset-Mock;Set-Content $script:trialJournal '{corrupt existing journal'
    Reject {Run-Trial} 'Existing recovery was adopted';Assert ($script:writes.Count -eq 0) 'Existing recovery caused writes'
    Reset-Mock
    Reject {Invoke-PCGpuClockTrial $script:original 100 200 $script:trialJournal $script:trialJournal $stop} 'Journal/report collision accepted'
    Reject {Invoke-PCGpuClockTrial $script:original 100 200 $script:trialJournal (Join-Path $dir 'absent/report.json') $stop} 'Unwritable initial report accepted'
    Assert ($script:writes.Count -eq 0) 'Persistence failure wrote clocks'
    Reject {Assert-PCClockTrialRunning $stop 2147483647 1} 'Dead owner accepted'
    # Repeated trials must measure all baselines before writing and retain every run.
    Reset-Mock;$script:rates=@(100,101,99,110,109,111);$r=Run-Trial 3
    Assert ($r.State -eq 'Completed' -and $r.ChangePercent -eq 10 -and $r.Comparison -eq 'Observed higher throughput') 'Repeated median comparison failed'
    Assert ($r.BeforeSummary.Count -eq 3 -and $r.AfterSummary.Count -eq 3 -and $script:runs -eq 6 -and $script:cooldowns -eq 5) 'Incorrect repeated run/cooldown count'
    Assert ($r.BeforeSummary.SpreadPercent -eq 2 -and $r.AfterRuns.Count -eq 3) 'Spread or individual runs lost'
    $saved=Get-Content $reportPath -Raw|ConvertFrom-Json
    Assert ($saved.Schema -eq 2 -and $saved.AfterRuns[2].EnvironmentAfter.PowerLimitWatts -eq 450 -and $saved.Restoration -eq 'Verified') 'Report persistence lost nested run data'
    Assert ((Format-PCClockTrialReport $r) -match '3/3 valid runs' -and (Format-PCClockTrialReport $r) -match 'Run 3:') 'Repeated text report missing run details'
    Reset-Mock;$script:rates=@(100,101,99,90,89,91);$r=Run-Trial 3
    Assert ($r.ChangePercent -eq -10 -and $r.Comparison -eq 'Observed lower throughput') 'Regression was not reported'
    Reset-Mock;$script:rates=@(100,130,99);$r=Run-Trial 3
    Assert ($r.State -eq 'Stopped' -and $script:writes.Count -eq 0 -and $r.BeforeRuns.Count -eq 3 -and $null -eq $r.ChangePercent) 'Noisy baseline applied offsets or lost results'
    Reset-Mock;$script:rates=@(100,101,99,110,110,150);$r=Run-Trial 3
    Assert ($r.Comparison -eq 'Inconclusive' -and $r.ChangePercent -eq 10 -and $r.Restoration -eq 'Verified' -and ($r.ComparisonReasons -join ' ') -match 'spread') 'Noisy retest was promoted to a gain'
    Reset-Mock;$script:rates=@(100,101,99,100,101,102);$r=Run-Trial 3
    Assert ($r.Comparison -eq 'Inconclusive' -and ($r.ComparisonReasons -join ' ') -match 'overlap') 'Overlapping ranges promoted to a gain'
    Reset-Mock 'warm-start';$r=Run-Trial 3
    Assert ($r.Comparison -eq 'Inconclusive' -and $r.AfterSummary.MedianStartGpuC -eq 60 -and ($r.ComparisonReasons -join ' ') -match 'temperatures') 'Warm starting conditions were hidden'
    foreach($mode in 'plan-change','baseline-mismatch','cancel-cooldown','power-before-apply'){
        Reset-Mock $mode;$r=Run-Trial 3
        Assert ($r.State -eq 'Stopped' -and $script:writes.Count -eq 0 -and $null -eq $r.ChangePercent) "Invalid repeated baseline applied: $mode"
    }
    foreach($mode in 'power-change','power-lost','cancel-late'){
        Reset-Mock $mode;$r=Run-Trial 3
        Assert ($r.State -eq 'Stopped' -and $r.Restoration -eq 'Verified' -and $r.Comparison -eq 'Unavailable' -and $null -eq $r.ChangePercent) "Retest change missed recovery: $mode"
        Assert ($r.BeforeRuns.Count -eq 3 -and $r.AfterRuns.Count -eq 1 -and $script:live.CoreMHz -eq 30) "Partial runs lost: $mode"
        Assert ((Get-Content $reportPath -Raw|ConvertFrom-Json).BeforeRuns.Count -eq 3) 'Partial report not saved'
    }
    Reset-Mock;$r=Run-Trial
    Assert ($r.Comparison -eq 'Inconclusive' -and ($r.ComparisonReasons -join ' ') -match 'one pair') 'Quick pair claimed repeatability'
    $r.State='Running';Save-PCClockJournal $r $reportPath
    $loaded=Read-PCClockTrialReport $reportPath
    Assert ($loaded.State -eq 'Interrupted' -and $loaded.Restoration -eq 'Unverified' -and $loaded.Comparison -eq 'Unavailable' -and $null -eq $loaded.ChangePercent -and $loaded.BeforeRuns.Count -eq 1) 'Interrupted reload claimed restored state or lost runs'
    Reject {Invoke-PCGpuClockTrial $script:original 100 200 $script:trialJournal $reportPath $stop -RunCount 2} 'Invalid run count accepted'
    # v0.25.0 exports stay readable.
    $legacy=[pscustomobject]@{Schema=1;Kind='PCInsight.GpuClockTrial';State='Completed';Device=$script:original;Requested=$r.Requested;Before=$r.BeforeRuns[0];After=$r.AfterRuns[0];ChangePercent=10;Restoration='Verified';Message='Legacy';Limitations='One pair'}
    Assert ((Format-PCClockTrialReport $legacy) -match 'one pair' -and (Format-PCClockTrialReport $legacy) -match 'Baseline:') 'Legacy report no longer readable'
    Save-PCClockJournal $legacy $reportPath;Assert ((Read-PCClockTrialReport $reportPath).Schema -eq 1) 'Legacy report loading failed'
    # History errors must never prevent restoration, or silently discard the prior result.
    $realArchive=${function:Save-PCClockTrialHistory}
    function Save-PCClockTrialHistory($Report,$Folder){throw 'Simulated history write error'}
    Reset-Mock;$r=Run-Trial
    Assert ($r.State -eq 'Completed' -and $r.Restoration -eq 'Verified' -and $r.Message -match 'history could not be saved' -and -not (Test-Path $script:trialJournal)) 'Archive failure bypassed recovery or was hidden'
    $script:writes.Clear();Reject {Run-Trial} 'Prior report overwritten when archive failed'
    Assert ($script:writes.Count -eq 0 -and (Read-PCClockTrialReport $reportPath).Id -eq $r.Id) 'Archive error changed clocks or lost prior report'
    Set-Item Function:Save-PCClockTrialHistory $realArchive
    'PASS: repeated medians/spread, noise/overlap/temperature gates, run checkpoints, power-setting changes/loss, legacy reports, baseline/retest comparison, selected adapter, cancellation before/during apply and retest, temperature loss/cutoff, external changes, partial writes, failed recovery, report errors and retained journals (mock hardware).'
}finally{Remove-Item $dir -Recurse -Force}
