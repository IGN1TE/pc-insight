# Separate background worker keeps cancellation responsive while GPU tests run.
$script:clockTrialJob=$null;$script:clockTrialResult=$null;$script:clockTrialOriginal=$null
$script:clockTrialReportPath=Join-Path $dataDir 'gpu-clock-trial.json'
$script:clockTrialStopPath=Join-Path $dataDir ('clock-trial-stop-'+[guid]::NewGuid().ToString('N')+'.signal')
$script:clockTrialTimer=[Windows.Threading.DispatcherTimer]::new()
$script:clockTrialTimer.Interval=[timespan]::FromMilliseconds(250)
function Update-PCClockTrialControls([bool]$Busy=$false) {
    $busy=$Busy -or (Test-PCClockUiBusy)
    $selected=$ui.ClockGPU.SelectedItem
    $ui.StartClockTrial.IsEnabled=-not $busy -and $script:isAdministrator -and $selected -and $selected.Available -and -not (Test-Path -LiteralPath $script:clockJournalPath)
    $ui.StopClockTrial.IsEnabled=$null -ne $script:clockTrialJob -and -not (Test-Path -LiteralPath $script:clockTrialStopPath)
    $ui.ExportClockTrial.IsEnabled=$null -ne $script:clockTrialResult -and -not $script:clockTrialJob
    $ui.ClockTrialMode.IsEnabled=-not $busy
}
function Stop-PCClockTrial {
    if(-not $script:clockTrialJob){return}
    Set-Content -LiteralPath $script:clockTrialStopPath -Value 'stop' -ErrorAction Stop
    $ui.ClockTrialStage.Text='Stopping workload and restoring offsets. Keep PC Insight open until restoration finishes.'
    Update-PCClockTrialControls
}
function Receive-PCClockTrial {
    if(-not $script:clockTrialJob){return}
    $records=@(Receive-Job $script:clockTrialJob -ErrorAction SilentlyContinue)
    foreach($record in $records){
        if($record.Kind -eq 'TrialStage' -and -not (Test-Path -LiteralPath $script:clockTrialStopPath)){$ui.ClockTrialStage.Text=$record.Value;$ui.ClockTrialProgress.Value=0}
        elseif($record.Kind -eq 'Progress'){$ui.ClockTrialProgress.Value=[math]::Max(0,[math]::Min(100,[double]$record.Value))}
        elseif($record.Kind -eq 'TrialResult'){$script:clockTrialResult=$record.Value}
    }
    if($script:clockTrialJob.State -notin @('Completed','Failed','Stopped')){return}
    try{
        if(-not $script:clockTrialResult){
            $errorText=($script:clockTrialJob.ChildJobs | ForEach-Object {$_.Error} | Out-String).Trim()
            if(-not $errorText){$errorText='The trial worker ended without a result.'}
            $recovery='No clock recovery record found.'
            # Start is blocked when any journal exists, so a new journal is from
            # this trial. Never discard it if this fallback recovery fails.
            if(Test-Path -LiteralPath $script:clockJournalPath){
                try{
                    $j=Read-PCClockJournal $script:clockJournalPath
                    $original=$script:clockTrialOriginal
                    if(-not $original -or $j.UUID -ne $original.UUID -or $j.OriginalCore -ne $original.CoreMHz -or $j.OriginalMemory -ne $original.MemoryMHz){throw 'The recovery record does not match the reviewed trial. Inspect it before restoring.'}
                    $recovery=Restore-PCGpuClockOffsets $script:clockJournalPath
                }catch{$recovery='Recovery required: '+$_.Exception.Message}
            }
            $ui.ClockTrialResult.Text=$errorText+"`n"+$recovery
            $ui.ClockTrialStage.Text='Trial interrupted. Review the recovery status below.'
        }else{
            $ui.ClockTrialResult.Text=Format-PCClockTrialReport $script:clockTrialResult
            $ui.ClockTrialStage.Text=$script:clockTrialResult.State+' | restoration: '+$script:clockTrialResult.Restoration
        }
        try{Refresh-PCClockDevices}catch{$ui.ClockStatus.Text=$_.Exception.Message}
        if(Test-Path -LiteralPath $script:clockJournalPath){$ui.ClockStatus.Text='Clock recovery is still pending. Use Restore saved clock offsets before another trial.'}
        else{$ui.ClockStatus.Text='No pending clock recovery record. Detect clock support to inspect current offsets.'}
    }finally{
        Remove-Job $script:clockTrialJob -Force -ErrorAction SilentlyContinue
        $script:clockTrialJob=$null;$script:clockActionBusy=$false;$script:clockTrialTimer.Stop()
        Remove-Item -LiteralPath $script:clockTrialStopPath -ErrorAction SilentlyContinue
        Set-Busy $false;Update-PCClockTrialControls
    }
}
$script:clockTrialTimer.Add_Tick({
    try{Receive-PCClockTrial}catch{$ui.ClockTrialStage.Text='Trial status error: '+$_.Exception.Message+'. Use Stop trial and restore.'}
})
$ui.StartClockTrial.Add_Click({
    if(Test-PCClockUiBusy){return}
    try{
        $selected=$ui.ClockGPU.SelectedItem
        if(-not $selected -or -not $selected.Available){throw 'Detect clock support first.'}
        if(Test-Path -LiteralPath $script:clockJournalPath){throw 'Restore saved clock offsets before starting a trial.'}
        $core=ConvertTo-PCClockInteger $ui.CoreOffset.Text;$memory=ConvertTo-PCClockInteger $ui.MemoryOffset.Text
        $runCount=[int]$ui.ClockTrialMode.SelectedItem.Tag
        if($runCount -notin @(1,3)){throw 'Select a trial length.'}
        $duration=if($runCount -eq 3){'about 5 minutes'}else{'about 90 seconds'}
        Assert-PCClockTargets $selected $core $memory
        if($core -eq $selected.CoreMHz -and $memory -eq $selected.MemoryMHz){throw 'Enter different offsets to measure a change.'}
        $script:clockActionBusy=$true;Set-Busy $true
        if(-not(Confirm "Run a temporary overclock trial on $($selected.Name)?`nGPU: $($selected.UUID)`nCore: $($selected.CoreMHz) -> $core MHz`nMemory: $($selected.MemoryMHz) -> $memory MHz`n`nThe app measures $runCount baseline run(s), applies these offsets, measures $runCount retest run(s), and restores the originals. Each run has a 5-second warm-up and 30-second measurement, with 10-second cooldowns. Allow $duration. A noisy three-run baseline stops before applying. Cancel or a failed test also attempts restoration.`n`nClose games and save your work. Unstable clocks can cause artifacts, driver resets, crashes or lost work. A short test does not prove stability. If the app, driver or PC crashes, use Restore saved clock offsets on the next launch. No voltage or power-limit changes are made.")){return}
        Remove-Item -LiteralPath $script:clockTrialStopPath -ErrorAction SilentlyContinue
        $script:clockTrialResult=$null;$ui.ClockTrialResult.Text='Preparing the measured trial...';$ui.ClockTrialStage.Text='Starting baseline';$ui.ClockTrialProgress.Value=0
        $script:clockTrialOriginal=$selected|Select-Object UUID,CoreMHz,MemoryMHz
        $script:clockTrialJob=Start-Job -ArgumentList $PSScriptRoot,$selected,$core,$memory,$script:clockJournalPath,$script:clockTrialReportPath,$script:clockTrialStopPath,$PID,(Get-Process -Id $PID).StartTime.Ticks,$runCount -ScriptBlock {
            param($root,$selected,$core,$memory,$journal,$report,$stopPath,$ownerId,$ownerStart,$runCount)
            $ErrorActionPreference='Stop'
            foreach($file in 'GpuOverclock.ps1','GpuClockTrial.ps1','Power.ps1','Tuning.ps1','Engine.ps1','Monitor.ps1','LiveMonitor.ps1','ExtendedTests.ps1','NativeSensors.ps1'){. (Join-Path $root $file)}
            try{
                Initialize-PCNativeSensors
                Invoke-PCGpuClockTrial $selected $core $memory $journal $report $stopPath $ownerId $ownerStart -RunCount $runCount
            }finally{Close-PCNativeSensors}
        }
        $script:clockTrialTimer.Start()
    }catch{$ui.ClockTrialStage.Text=$_.Exception.Message;Show-Error $_.Exception.Message}
    finally{
        if(-not $script:clockTrialJob){$script:clockActionBusy=$false;Set-Busy $false}
        else{$ui.Cancel.IsEnabled=$false;$ui.SensorCancel.IsEnabled=$false}
        Update-PCClockTrialControls
    }
})
$ui.StopClockTrial.Add_Click({try{Stop-PCClockTrial}catch{Show-Error $_.Exception.Message}})
$ui.ExportClockTrial.Add_Click({
    if(-not $script:clockTrialResult -or $script:clockTrialJob){return}
    try{
        $json=$script:clockTrialResult|ConvertTo-Json -Depth 8
        $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON report (*.json)|*.json';$dialog.FileName='PC-Insight-GPU-clock-trial.json'
        if($dialog.ShowDialog() -eq $true){[IO.File]::WriteAllText($dialog.FileName,$json,[Text.UTF8Encoding]::new($false))}
    }catch{Show-Error $_.Exception.Message}
})
if(Test-Path -LiteralPath $script:clockTrialReportPath){
    try{
        $saved=Read-PCClockTrialReport $script:clockTrialReportPath
        $script:clockTrialResult=$saved
        $ui.ClockTrialResult.Text=Format-PCClockTrialReport $saved
        $ui.ClockTrialStage.Text='Previous trial (saved result; not a fresh hardware check)'
    }catch{$ui.ClockTrialResult.Text='Saved trial report could not be read: '+$_.Exception.Message}
}
Update-PCClockTrialControls
