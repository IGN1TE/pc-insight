# Uses the app's shared job slot so benchmarks, tuning, updates and CPU trials cannot overlap.
$script:cpuTrialFolder=Join-Path $script:dataDir 'cpu-tuning-trials'
$script:cpuDetected=$null;$script:cpuActiveId=$null;$script:cpuCancelAt=$null
$script:cpuStopPath=Join-Path $script:dataDir ('cpu-stop-'+[guid]::NewGuid().ToString('N')+'.signal')
function Test-PCCpuUiBusy {
    $script:job -or $script:updateJob -or $script:clockActionBusy -or $script:clockTrialJob -or
        ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))
}
function Update-PCCpuControls {
    $busy=Test-PCCpuUiBusy
    $ui.CpuDetect.IsEnabled=-not $busy
    $ui.CpuBaseline.IsEnabled=-not $busy -and $null -ne $script:cpuDetected
    $canRetest=$false
    $entry=$ui.CpuHistory.SelectedItem
    if($entry -and $entry.Report.State -in @('Ready','Completed')){
        try{$canRetest=(Get-PCCpuBatchSummary $entry.Report.BeforeRuns).SpreadPercent -le 5}catch{}
    }
    $ui.CpuRetest.IsEnabled=-not $busy -and $canRetest
    $ui.CpuStop.IsEnabled=$null -ne $script:job -and $script:jobKind -eq 'cpu-tuning' -and -not $script:cpuCancelAt
    $ui.CpuNote.IsEnabled=-not $busy
    $ui.CpuExport.IsEnabled=$null -ne $entry
}
function Refresh-PCCpuHistory([string]$SelectId) {
    if(-not $SelectId -and $ui.CpuHistory.SelectedItem){$SelectId=$ui.CpuHistory.SelectedItem.Id}
    $catalog=Get-PCCpuTrialHistory $script:cpuTrialFolder
    $ui.CpuHistory.ItemsSource=@($catalog.Entries)
    $selected=@($catalog.Entries|Where-Object Id -eq $SelectId|Select-Object -First 1)
    if($selected.Count){$ui.CpuHistory.SelectedItem=$selected[0]}elseif($catalog.Entries.Count){$ui.CpuHistory.SelectedIndex=0}
    $ui.CpuHistoryStatus.Text=(@($catalog.Issues) -join "`n")
    $ui.CpuResult.Text=Format-PCCpuTrial $ui.CpuHistory.SelectedItem.Report
    Update-PCCpuControls
}
function Start-PCCpuTask([ValidateSet('Detect','Baseline','Retest')][string]$Mode) {
    if(Test-PCCpuUiBusy){return}
    $report=$null
    try {
        if($Mode -ne 'Detect'){
            if($Mode -eq 'Baseline' -and -not $script:cpuDetected){throw 'Detect the CPU platform before collecting a baseline.'}
            $report=New-PCCpuTrial $Mode $ui.CpuNote.Text $ui.CpuHistory.SelectedItem.Report
            if(-not(Confirm "$Mode measures three 60-second CPU runs, with cooldowns (about 4 minutes). It stops at the 85 C preview cutoff or if required readings fail. Save other work and keep cooling and background tasks consistent. This is not a stability test. PC Insight does not apply or restore CPU clocks, voltage, or BIOS settings. Start measurement?")){return}
            Save-PCCpuTrial $report $script:cpuTrialFolder
        }
        Remove-Item -LiteralPath $script:cpuStopPath -ErrorAction SilentlyContinue
        $script:cpuActiveId=if($report){$report.Id}else{$null};$script:cpuCancelAt=$null
        $script:jobKind='cpu-tuning';$script:taskStarted=Get-Date;$script:cpuReceived=$false
        $script:job=Start-Job -ArgumentList $PSScriptRoot,$Mode,$report,$script:cpuTrialFolder,$script:cpuStopPath,$PID,([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks) -ScriptBlock {
            param($root,$mode,$report,$folder,$stopPath,$ownerId,$ownerTicks)
            $ErrorActionPreference='Stop'
            . "$root/Power.ps1";. "$root/Monitor.ps1";. "$root/NativeSensors.ps1";. "$root/CpuTuning.ps1"
            $guard={
                if(Test-Path -LiteralPath $stopPath){throw 'CPU measurement stopped by the user. Completed runs remain saved.'}
                $owner=Get-Process -Id $ownerId -ErrorAction SilentlyContinue
                if(-not $owner -or $owner.StartTime.ToUniversalTime().Ticks -ne $ownerTicks){throw 'The app session ended. CPU measurement stopped.'}
            }
            & $guard
            if($mode -eq 'Detect'){[pscustomobject]@{Kind='CpuContext';Value=(Get-PCCpuTuningContext)};return}
            try{Initialize-PCNativeSensors;Invoke-PCCpuTrial $report $folder $guard}finally{Close-PCNativeSensors}
        }
        Set-Busy $true
        $ui.CpuProgress.Value=0;$ui.CpuStage.Text=if($Mode -eq 'Detect'){'Reading CPU platform...'}else{"$Mode measurements running. Each completed run is saved."}
        Update-PCCpuControls
    }catch{
        $ui.CpuStage.Text=$_.Exception.Message
        if(-not $script:job){$script:cpuActiveId=$null;Set-Busy $false;Refresh-PCCpuHistory}
    }
}
function Stop-PCCpuTask {
    if(-not $script:job -or $script:jobKind -ne 'cpu-tuning' -or $script:cpuCancelAt){return}
    [IO.File]::WriteAllText($script:cpuStopPath,'stop')
    $script:cpuCancelAt=Get-Date
    $ui.CpuStage.Text='Stopping CPU measurement. Waiting for the worker to finish; completed runs stay saved.'
    Update-PCCpuControls
}
function Receive-PCCpuTask {
    $finished=$false
    try {
        if(((Get-Date)-$script:taskStarted).TotalSeconds -gt 600 -and -not $script:cpuCancelAt){Stop-PCCpuTask}
        if($script:cpuCancelAt -and ((Get-Date)-$script:cpuCancelAt).TotalSeconds -gt 15){Stop-Job $script:job -ErrorAction SilentlyContinue}
        $terminal=$script:job.State -in @('Completed','Failed','Stopped')
        foreach($item in @(Receive-Job $script:job -ErrorAction Stop)){
            switch($item.Kind){
                'CpuContext' {
                    $script:cpuDetected=$item.Value;$script:cpuReceived=$true;$c=$item.Value
                    $ui.CpuPlatform.Text="$($c.CPU) | $($c.Cores) cores / $($c.Threads) threads`n$($c.Board) | BIOS $($c.BIOS)`nMemory: $($c.Memory)`nCPU ratio, voltage and power-limit writes: unavailable in this preview. CPU model alone does not establish overclocking support."
                    $ui.CpuStage.Text='Platform detected. Describe the current settings, then collect a baseline.'
                }
                'CpuReport' {$script:cpuReceived=$true;$ui.CpuStage.Text=$item.Value.Message;$ui.CpuProgress.Value=if($item.Value.State -in @('Ready','Completed')){100}else{0}}
                'CpuStatus' {if(-not $script:cpuCancelAt){$ui.CpuStage.Text=[string]$item.Value}}
                'Progress' {$ui.CpuProgress.Value=$item.Value}
                'Frame' {Show-SensorFrame $item.Value}
            }
        }
        if(-not $terminal){return}
        $finished=$true
        if($script:job.State -ne 'Completed' -or -not $script:cpuReceived){throw 'CPU task ended without a final report. Completed checkpoints remain saved; any unfinished experiment is shown as interrupted.'}
    }catch{
        $finished=$true
        Stop-Job $script:job -ErrorAction SilentlyContinue
        $ui.CpuStage.Text=$_.Exception.Message
    }finally{
        if($finished){
            Remove-Job $script:job -Force -ErrorAction SilentlyContinue;$script:job=$null;$script:cpuCancelAt=$null
            Remove-Item -LiteralPath $script:cpuStopPath -ErrorAction SilentlyContinue
            Set-Busy $false;Refresh-PCCpuHistory $script:cpuActiveId;$script:cpuActiveId=$null
        }
    }
}
function Select-PCCpuExportPath {
    $dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='JSON report (*.json)|*.json';$dialog.FileName='PC-Insight-CPU-experiment.json'
    if($dialog.ShowDialog($script:window)){$dialog.FileName}
}
$ui.CpuDetect.Add_Click({Start-PCCpuTask 'Detect'})
$ui.CpuBaseline.Add_Click({Start-PCCpuTask 'Baseline'})
$ui.CpuRetest.Add_Click({Start-PCCpuTask 'Retest'})
$ui.CpuStop.Add_Click({try{Stop-PCCpuTask}catch{Show-Error $_.Exception.Message}})
$ui.CpuHistory.Add_SelectionChanged({$ui.CpuResult.Text=Format-PCCpuTrial $ui.CpuHistory.SelectedItem.Report;Update-PCCpuControls})
$ui.CpuExport.Add_Click({
    try {
        if(-not $ui.CpuHistory.SelectedItem){return}
        # Freeze selection before opening the file dialog; never export a moving worker object.
        $copy=$ui.CpuHistory.SelectedItem.Report|ConvertTo-Json -Depth 12|ConvertFrom-Json
        $export=[pscustomobject]@{Kind='PCInsight.CpuTuningExport';Schema=1;Experiment=$copy;Comparison=(Compare-PCCpuTrial $copy)}
        $path=Select-PCCpuExportPath
        if($path){Save-JsonAtomic $export $path;$ui.CpuHistoryStatus.Text='CPU experiment exported. Hardware details and user notes are included.'}
    }catch{Show-Error $_.Exception.Message}
})
Refresh-PCCpuHistory
