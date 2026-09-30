# All native writes and workload execution are mocked. Real journal/recovery logic runs.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GpuOverclock.ps1"
. "$PSScriptRoot/../GpuClockTrial.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$Action,$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-clock-trial-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$script:trialJournal=Join-Path $dir 'restore.json';$reportPath=Join-Path $dir 'trial.json';$stop=Join-Path $dir 'stop.signal'
$script:original=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Driver='mock-1';Available=$true;CoreMHz=30;MemoryMHz=40;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
$script:realSave=${function:Save-PCClockJournal}
function Reset-Mock([string]$Mode='normal'){
    $script:mode=$Mode;$script:live=$script:original|Select-Object *;$script:writes=[Collections.Generic.List[object]]::new()
    $script:runs=0;$script:saveFailed=$false;$script:memoryFailed=$false
    Get-ChildItem $dir -File|Remove-Item
}
function Test-PCClockAdministrator {$script:mode -ne 'nonadmin'}
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
    Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
    Assert-PCClockTrialState $Expected
}
function Invoke-PCClockTrialMeasurement($Expected,$StopPath,$OwnerId,$OwnerStart){
    $script:runs++
    Assert-PCClockTrialRunning $StopPath $OwnerId $OwnerStart
    Assert-PCClockTrialState $Expected
    if($script:runs -eq 1){
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
    $rate=if($script:runs -eq 1){100}else{110}
    if($script:mode -eq 'invalid-score' -and $script:runs -eq 2){$rate=[double]::NaN}
    $renderer=if($script:mode -eq 'incompatible' -and $script:runs -eq 2){'Mock GPU different renderer'}else{'Mock GPU/PCIe'}
    [pscustomobject]@{Kind='Progress';Value=50}
    [pscustomobject]@{Kind='Result';Value=[pscustomobject]@{
        Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';Timestamp=[datetimeoffset]::Now.ToString('o');Seconds=30;Runtime='4.0';Renderer=$renderer;GPUName=$name;WarmupSeconds=5
        Completed=($script:mode -ne 'incomplete');StopReason=$(if($script:mode -eq 'incomplete'){'GPU stopped'}else{$null});GpuFramesPerSecond=$rate
        Frames=@([pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu-nvidia/0';Type='Temperature';Name='GPU Core';HardwareName=$name;Value=65})})
    }}
}
function Run-Trial {
    $events=@(Invoke-PCGpuClockTrial ($script:original|Select-Object *) 100 200 $script:trialJournal $reportPath $stop)
    $results=@($events|Where-Object Kind -eq 'TrialResult')
    Assert ($results.Count -eq 1) 'Trial did not emit exactly one final result'
    $results[0].Value
}
try{
    Reset-Mock
    $r=Run-Trial
    Assert ($r.State -eq 'Completed' -and $r.Restoration -eq 'Verified' -and $r.ChangePercent -eq 10) "Successful comparison/restoration failed: $($r|ConvertTo-Json -Depth 5 -Compress)"
    Assert ($script:runs -eq 2 -and $script:live.CoreMHz -eq 30 -and $script:live.MemoryMHz -eq 40 -and -not (Test-Path $script:trialJournal)) 'Successful trial left offsets applied'
    Assert ($r.Before.PeakGpuC -eq 65 -and $r.Before.TemperatureSamples -eq 1) 'Temperature summary missing'
    Assert ((Get-Content $reportPath -Raw|ConvertFrom-Json).Restoration -eq 'Verified') 'Saved report missed restoration'
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
    foreach($mode in 'nonadmin','multiple'){
        Reset-Mock $mode;Reject {Run-Trial} "Preflight accepted $mode";Assert ($script:writes.Count -eq 0) 'Preflight performed a write'
    }
    Reset-Mock;Set-Content $script:trialJournal '{corrupt existing journal'
    Reject {Run-Trial} 'Existing recovery was adopted';Assert ($script:writes.Count -eq 0) 'Existing recovery caused writes'
    Reset-Mock
    Reject {Invoke-PCGpuClockTrial $script:original 100 200 $script:trialJournal $script:trialJournal $stop} 'Journal/report collision accepted'
    Reject {Invoke-PCGpuClockTrial $script:original 100 200 $script:trialJournal (Join-Path $dir 'absent/report.json') $stop} 'Unwritable initial report accepted'
    Assert ($script:writes.Count -eq 0) 'Persistence failure wrote clocks'
    Reject {Assert-PCClockTrialRunning $stop 2147483647 1} 'Dead owner accepted'
    'PASS: baseline/retest comparison, selected adapter, cancellation before/during apply and retest, temperature loss/cutoff, external changes, partial writes, failed recovery, report errors and retained journals (mock hardware).'
}finally{Remove-Item $dir -Recurse -Force}
