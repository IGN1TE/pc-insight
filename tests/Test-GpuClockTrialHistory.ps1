# Pure saved-data tests. No driver calls or hardware changes.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GpuOverclock.ps1"
. "$PSScriptRoot/../GpuClockTrial.ps1"
. "$PSScriptRoot/../Tuning.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$Action,$message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $message}
function Copy-Record($Value){$Value|ConvertTo-Json -Depth 10|ConvertFrom-Json}
function New-Trial([double]$After=110,[int]$Core=100){
    $device=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Driver='mock-1';CoreMHz=0;MemoryMHz=0}
    $context=[pscustomobject]@{UUID=$device.UUID;Driver=$device.Driver;Plan='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';PowerLimitWatts=450}
    $report=[pscustomobject]@{
        Schema=2;Kind='PCInsight.GpuClockTrial';Id=[guid]::NewGuid().ToString('N');Started=[datetimeoffset]::Now.ToString('o');Finished=[datetimeoffset]::Now.ToString('o')
        State='Completed';Stage='Finished';Device=$device;Requested=[pscustomobject]@{CoreMHz=$Core;MemoryMHz=200};RunCount=3;RunIndex=3
        Environment=$context;BeforeRuns=@();AfterRuns=@();BeforeSummary=$null;AfterSummary=$null;Comparison='Unused cached text';ComparisonReasons=@()
        ChangePercent=999;Restoration='Verified';Message='Test fixture';Limitations='Mock data'
    }
    foreach($side in 'Before','After'){
        $rate=if($side -eq 'Before'){100}else{$After}
        $report.($side+'Runs')=@(1..3|ForEach-Object {
            [pscustomobject]@{Test='OpenGL-1280x720-256shader-b8-w5-30s-v2';Timestamp=$report.Started;Seconds=30;Runtime='4.0';Renderer='Mock GPU/PCIe';GPUName='Mock GPU';WarmupSeconds=5;Completed=$true;StopReason=$null;DrawsPerSecond=($rate+$_-2);PeakGpuC=65;TemperatureSamples=30;RunIndex=$_;StartGpuC=50;EnvironmentBefore=(Copy-Record $context);EnvironmentAfter=(Copy-Record $context);Eligible=$true;Exclusion=$null}
        })
    }
    $report
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-trial-history-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dir
$last=Join-Path $dir 'gpu-clock-trial.json';$folder=Get-PCClockTrialHistoryFolder $last
try{
    $a=New-Trial;$b=New-Trial 120 150
    Save-PCClockTrialHistory $a $folder;Save-PCClockTrialHistory $a $folder;Save-PCClockTrialHistory $b $folder
    $catalog=Get-PCClockTrialHistory $folder
    Assert ($catalog.Entries.Count -eq 2 -and $catalog.Issues.Count -eq 0) 'History duplicated or lost an experiment'
    Assert ($catalog.Entries[0].Id -eq $b.Id -and $catalog.Entries[0].Label -match '150') 'History ordering/label incorrect'
    $bad=Copy-Record $a;$bad.Id='../escape';Reject {Save-PCClockTrialHistory $bad $folder} 'Path escape accepted'
    $bad=Copy-Record $a;$bad.Device.UUID='GPU-11111111-2222-3333-4444-555555555555'
    Reject {Save-PCClockTrialHistory $bad $folder} 'Archive identity collision overwrote another GPU'
    Assert ((Read-PCClockTrialReport (Join-Path $folder ($a.Id+'.json'))).Device.UUID -eq $a.Device.UUID) 'Collision damaged original'
    $corrupt=Join-Path $folder (([guid]::NewGuid().ToString('N'))+'.json');Set-Content $corrupt '{broken'
    $catalog=Get-PCClockTrialHistory $folder
    Assert ($catalog.Entries.Count -eq 2 -and $catalog.Issues.Count -eq 1 -and (Test-Path $corrupt)) 'One corrupt archive hid valid trials or was deleted'
    Assert ((Get-PCClockTrialHistory $folder -Limit 1).Entries.Count -eq 1 -and @(Get-ChildItem $folder).Count -eq 3) 'Picker limit deleted archived data'
    $partial=New-Trial;$partial.State='Running';$partial.Restoration='Not needed';$partial.AfterRuns=@();Save-PCClockJournal $partial $last
    Protect-PCPreviousClockTrial $last
    $restored=Read-PCClockTrialReport (Join-Path $folder ($partial.Id+'.json'))
    Assert ($restored.State -eq 'Interrupted' -and $restored.Restoration -eq 'Unverified' -and $restored.BeforeRuns.Count -eq 3) 'Partial checkpoint was not preserved conservatively'
    Assert ((Get-Content $last -Raw|ConvertFrom-Json).State -eq 'Running') 'Archiving altered the last-run checkpoint'
    $older=Copy-Record $a;$older.State='Interrupted';$older.Restoration='Unverified';Save-PCClockTrialHistory $older $folder
    Assert ((Read-PCClockTrialReport (Join-Path $folder ($a.Id+'.json'))).Restoration -eq 'Verified') 'Old checkpoint replaced final restoration'
    $c=Compare-PCClockTrials $a $b
    Assert ($c.Compatible -and $c.ChangePercent -eq 9.09 -and $c.Before.Median -eq 110 -and $c.After.Median -eq 120 -and $c.Quality -eq 'Observed higher throughput in B') 'Compatible comparison or summary recalculation failed'
    Assert ((Format-PCClockTrialComparison $c $a $b) -match '9.09' -and (Format-PCClockTrialComparison $c $a $b) -match '150') 'Readable comparison missing scores/offsets'
    Assert (-not (Compare-PCClockTrials $a $a).Compatible) 'Same trial compared to itself'
    $mutations=@(
        {$args[0].Device.UUID='GPU-11111111-2222-3333-4444-555555555555'},
        {$args[0].Device.Driver='new-driver'},
        {$args[0].Device.CoreMHz=10},
        {$args[0].Environment.PowerLimitWatts=400},
        {$args[0].Environment.Plan='11111111-2222-3333-4444-555555555555'},
        {$args[0].Schema=1},{$args[0].RunCount=1},{$args[0].State='Stopped'},{$args[0].Restoration='RecoveryRequired'},
        {$args[0].AfterRuns[2].RunIndex=1},{$args[0].AfterRuns[1].Eligible=$false},
        {$args[0].AfterRuns[1].EnvironmentAfter=$null},{$args[0].AfterRuns[1].DrawsPerSecond=[double]::NaN},
        {$args[0].BeforeRuns[1].Renderer='Other renderer'}
    )
    foreach($change in $mutations){
        $bad=Copy-Record $b;& $change $bad;$c=Compare-PCClockTrials $a $bad
        Assert (-not $c.Compatible -and $null -eq $c.ChangePercent -and $c.Reasons.Count) "Invalid experiment compared: $change"
    }
    $bad=Copy-Record $b
    foreach($run in @($bad.BeforeRuns)+@($bad.AfterRuns)){$run.Seconds=33}
    $bad.AfterRuns[2].Seconds=36;$c=Compare-PCClockTrials $a $bad
    Assert (-not $c.Compatible) 'Transitive duration tolerance admitted an incompatible run'
    $drift=Copy-Record $b;foreach($run in $drift.BeforeRuns){$run.DrawsPerSecond+=10}
    $c=Compare-PCClockTrials $a $drift
    Assert ($c.Compatible -and $c.Quality -eq 'Inconclusive' -and ($c.Reasons -join ' ') -match 'Original-setting') 'Baseline drift was presented as a tuning gain'
    $warm=Copy-Record $b;foreach($run in @($warm.BeforeRuns)+@($warm.AfterRuns)){$run.StartGpuC=60}
    $c=Compare-PCClockTrials $a $warm
    Assert ($c.Quality -eq 'Inconclusive' -and ($c.Reasons -join ' ') -match 'temperatures') 'Cross-experiment temperature difference was hidden'
    $overlap=New-Trial 111 150;$c=Compare-PCClockTrials $a $overlap
    Assert ($c.Quality -eq 'Inconclusive' -and ($c.Reasons -join ' ') -match 'ranges overlap between') 'Overlapping retest ranges presented as a gain'
    $sameOffsets=New-Trial 120 100;$c=Compare-PCClockTrials $a $sameOffsets
    Assert ($c.Quality -eq 'Inconclusive' -and ($c.Reasons -join ' ') -match 'same offsets') 'Same offsets presented as a new tuning setting'
    $device=[pscustomobject]@{UUID=$a.Device.UUID;Name='Mock GPU';Driver='mock-1';Available=$true;CoreMHz=0;MemoryMHz=0;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
    $values=Get-PCSavedClockTrialOffsets $b $device
    Assert ($values.CoreMHz -eq 150 -and $values.MemoryMHz -eq 200 -and $device.CoreMHz -eq 0) 'Loading inputs changed hardware state or chose wrong values'
    $device.Driver='new';Reject {Get-PCSavedClockTrialOffsets $b $device} 'Stale driver preset accepted'
    $device.Driver='mock-1';$device.CoreMax=100;Reject {Get-PCSavedClockTrialOffsets $b $device} 'Out-of-range saved offset accepted'
    Reject {Get-PCSavedClockTrialOffsets $partial $device} 'Interrupted trial supplied inputs'
    'PASS: durable/deduplicated archives, interruption recovery, corrupt-file isolation, compatible experiment comparison, drift/temperature/overlap gates and read-only offset loading.'
}finally{Remove-Item $dir -Recurse -Force}
