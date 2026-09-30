# CPU experiments measure user-managed settings. This module never writes CPU settings.
function Get-PCCpuTuningContext {
    $cpu=@(Get-CimInstance Win32_Processor -OperationTimeoutSec 8 -ErrorAction Stop)
    $board=@(Get-CimInstance Win32_BaseBoard -OperationTimeoutSec 8 -ErrorAction Stop)
    $bios=@(Get-CimInstance Win32_BIOS -OperationTimeoutSec 8 -ErrorAction Stop)
    $ram=@(Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec 8 -ErrorAction Stop)
    $os=@(Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop)
    if($cpu.Count -ne 1 -or $board.Count -ne 1 -or $bios.Count -ne 1 -or $os.Count -ne 1 -or -not $ram.Count){throw 'CPU experiments require one identified processor, motherboard, BIOS, OS and populated memory inventory.'}
    if([string]::IsNullOrWhiteSpace([string]$board[0].Manufacturer) -or [string]::IsNullOrWhiteSpace([string]$board[0].Product)){throw 'Motherboard identity is incomplete.'}
    foreach($dimm in $ram){if($dimm.Capacity -le 0 -or $dimm.ConfiguredClockSpeed -le 0){throw 'Configured memory information is unavailable. CPU comparison cannot be established.'}}
    $context=[pscustomobject]@{
        CPU=([string]$cpu[0].Name).Trim();Manufacturer=([string]$cpu[0].Manufacturer).Trim()
        Cores=[int]$cpu[0].NumberOfCores;Threads=[int]$cpu[0].NumberOfLogicalProcessors
        Board=(([string]$board[0].Manufacturer).Trim()+' / '+([string]$board[0].Product).Trim())
        BIOS=([string]$bios[0].SMBIOSBIOSVersion).Trim();OS=([string]$os[0].Version).Trim()
        Memory=(@($ram|Sort-Object DeviceLocator,Capacity,ConfiguredClockSpeed|ForEach-Object{'{0}:{1}:{2}' -f $_.DeviceLocator,$_.Capacity,$_.ConfiguredClockSpeed}) -join '; ')
        Plan=(Get-ActivePlan);Runtime=[Environment]::Version.ToString()
    }
    Assert-PCCpuTuningContext $context
    $context
}
function Assert-PCCpuTuningContext($Context) {
    foreach($key in 'CPU','Manufacturer','Board','BIOS','OS','Memory','Runtime'){
        if([string]::IsNullOrWhiteSpace([string]$Context.$key)){throw "Missing CPU comparison context: $key."}
    }
    if($Context.Cores -lt 1 -or $Context.Threads -lt $Context.Cores -or $Context.Plan -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$'){throw 'Invalid CPU topology or Windows power-plan identity.'}
}
function Assert-PCCpuContextMatch($Reference,$Current) {
    Assert-PCCpuTuningContext $Reference;Assert-PCCpuTuningContext $Current
    foreach($key in 'CPU','Manufacturer','Cores','Threads','Board','BIOS','OS','Memory','Plan','Runtime'){
        if([string]$Reference.$key -cne [string]$Current.$key){throw "CPU comparison context changed: $key. Collect a new baseline with matching conditions."}
    }
}
function Test-PCCpuNumber($Value,[double]$Min,[double]$Max) {
    if($null -eq $Value -or $Value -is [bool]){return $false}
    $number=0.0
    [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and
        -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -ge $Min -and $number -le $Max
}
function Assert-PCCpuRun($Run,$Reference) {
    if($Run.Completed -ne $true -or $Run.StopReason -or $Run.Test -ne 'SHA256-1MiB-parallel-60s-v1' -or
        -not (Test-PCCpuNumber $Run.Seconds 59.5 70) -or -not (Test-PCCpuNumber $Run.MiBPerSecond 0.01 100000000) -or
        -not (Test-PCCpuNumber $Run.Workers 1 16) -or [int]$Run.Workers -ne [double]$Run.Workers -or
        -not (Test-PCCpuNumber $Run.StartCPU 0.01 84.999) -or -not (Test-PCCpuNumber $Run.PeakCPU 0.01 84.999) -or
        $Run.PeakCPU -lt $Run.StartCPU -or $Run.TemperatureSamples -lt 15){throw 'CPU run is incomplete or has invalid score, duration or temperature coverage.'}
    Assert-PCCpuContextMatch $Reference.ContextBefore $Run.ContextBefore
    Assert-PCCpuContextMatch $Run.ContextBefore $Run.ContextAfter
    if($Run.Runtime -cne $Run.ContextBefore.Runtime -or $Run.Workers -ne $Reference.Workers){throw 'CPU workload runtime or worker count changed.'}
}
function Get-PCCpuBatchSummary($Runs) {
    $rows=@($Runs)
    if($rows.Count -ne 3 -or (@($rows.RunIndex|Sort-Object) -join ',') -ne '1,2,3'){throw 'Three distinct completed CPU runs are required.'}
    foreach($row in $rows){Assert-PCCpuRun $row $rows[0]}
    $scores=@($rows.MiBPerSecond|ForEach-Object{[double]$_}|Sort-Object)
    $starts=@($rows.StartCPU|ForEach-Object{[double]$_}|Sort-Object)
    $peaks=@($rows.PeakCPU|ForEach-Object{[double]$_}|Sort-Object)
    [pscustomobject]@{Median=$scores[1];Min=$scores[0];Max=$scores[2];SpreadPercent=(100*($scores[2]-$scores[0])/$scores[1]);StartCPU=$starts[1];PeakCPU=$peaks[1]}
}
function Compare-PCCpuTrial($Report) {
    $result=[pscustomobject]@{Verdict='Unavailable';ChangePercent=$null;Before=$null;After=$null;Reasons=@()}
    try {
        if($Report.State -ne 'Completed'){throw 'A completed baseline and retest are required.'}
        $result.Before=Get-PCCpuBatchSummary $Report.BeforeRuns;$result.After=Get-PCCpuBatchSummary $Report.AfterRuns
        foreach($run in $Report.AfterRuns){Assert-PCCpuRun $run $Report.BeforeRuns[0]}
        $result.ChangePercent=[math]::Round(100*($result.After.Median/$result.Before.Median-1),2)
        $reasons=[Collections.Generic.List[string]]::new()
        if($result.Before.SpreadPercent -gt 5 -or $result.After.SpreadPercent -gt 5){$reasons.Add('At least one batch exceeds the 5% variability heuristic.')}
        if([math]::Abs($result.After.StartCPU-$result.Before.StartCPU) -gt 5){$reasons.Add('Median starting CPU temperatures differ by more than 5 C.')}
        if($result.After.Min -le $result.Before.Max -and $result.Before.Min -le $result.After.Max){$reasons.Add('Observed score ranges overlap.')}
        $result.Reasons=@($reasons.ToArray())
        $result.Verdict=if($reasons.Count){'Inconclusive'}elseif($result.ChangePercent -gt 0){'Higher measured throughput'}else{'Lower measured throughput'}
    }catch{$result.ChangePercent=$null;$result.Reasons=@($_.Exception.Message)}
    $result
}
function New-PCCpuTrial([ValidateSet('Baseline','Retest')][string]$Mode,[string]$Note,$Source) {
    $note=$Note.Trim()
    if($note.Length -lt 1 -or $note.Length -gt 500){throw 'Describe the settings in 1 to 500 characters. Notes are user reported, not verified settings.'}
    $before=@();$parent=$null;$baselineNote=$note;$changeNote=''
    if($Mode -eq 'Retest'){
        if(-not $Source -or $Source.State -notin @('Ready','Completed')){throw 'Select a completed baseline or experiment before retesting.'}
        if((Get-PCCpuBatchSummary $Source.BeforeRuns).SpreadPercent -gt 5){throw 'Baseline variability exceeds 5%. Collect a more repeatable baseline first.'}
        $before=@(($Source.BeforeRuns|ConvertTo-Json -Depth 12|ConvertFrom-Json));$parent=$Source.Id;$baselineNote=$Source.BaselineNote;$changeNote=$note
    }
    [pscustomobject]@{Kind='PCInsight.CpuTuning';Schema=1;Id=[guid]::NewGuid().ToString('N');ParentId=$parent;Started=(Get-Date).ToString('o');State='Running';Mode=$Mode
        BaselineNote=$baselineNote;ChangeNote=$changeNote;BeforeRuns=$before;AfterRuns=@();Message='Preparing measurements.'
        Limitations='CPU settings are changed and restored externally. Notes are not verified settings. This SHA-256 workload is not a stability test or game benchmark. No CPU ratio, voltage, power-limit or firmware writes; no automatic CPU restore. Clocks, voltage settings, memory timings, power-plan subsettings and background activity are not verified. Boundary context checks cannot detect transient changes. Temperature samples can miss transients; hardware sample age is unknown.'}
}
function Save-PCCpuTrial($Report,[string]$Folder) {
    if($Report.Id -notmatch '^[a-fA-F0-9]{32}$'){throw 'Invalid CPU experiment identity.'}
    $null=[IO.Directory]::CreateDirectory($Folder)
    Save-JsonAtomic $Report (Join-Path $Folder ($Report.Id+'.json'))
}
function Read-PCCpuTrial([string]$Path) {
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.Length -gt 524288 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'CPU record is too large or is a linked file.'}
    $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    $date=[datetimeoffset]::MinValue
    if($r.Kind -ne 'PCInsight.CpuTuning' -or $r.Schema -ne 1 -or $r.Id -notmatch '^[a-fA-F0-9]{32}$' -or $file.BaseName -ne $r.Id -or
        -not [datetimeoffset]::TryParse([string]$r.Started,[ref]$date) -or $r.Mode -notin @('Baseline','Retest') -or
        $r.State -notin @('Running','Ready','Completed','Stopped','Interrupted') -or @($r.BeforeRuns).Count -gt 3 -or @($r.AfterRuns).Count -gt 3){throw 'Invalid CPU experiment record.'}
    if($r.State -eq 'Running'){$r.State='Interrupted';$r.Message='The previous app session ended during measurement. Completed runs were retained; no CPU settings were restored by this app.'}
    $r
}
function Get-PCCpuTrialHistory([string]$Folder) {
    $entries=[Collections.Generic.List[object]]::new();$issues=[Collections.Generic.List[string]]::new()
    if(Test-Path -LiteralPath $Folder){
        foreach($file in @(Get-ChildItem -LiteralPath $Folder -Filter '*.json' -File|Sort-Object LastWriteTimeUtc -Descending)){
            try {
                $r=Read-PCCpuTrial $file.FullName
                $entries.Add([pscustomobject]@{Id=$r.Id;Report=$r;Label=('{0} | {1} | {2} | {3}' -f ([datetimeoffset]::Parse($r.Started).ToLocalTime().ToString('yyyy-MM-dd HH:mm')),$r.Mode,$r.State,$r.Id.Substring(0,6))})
                if($entries.Count -ge 50){break}
            }catch{$issues.Add("Could not read $($file.Name): $($_.Exception.Message) File retained.")}
        }
    }
    [pscustomobject]@{Entries=@($entries.ToArray());Issues=@($issues.ToArray())}
}
function Invoke-PCCpuTrial($Report,[string]$Folder,[scriptblock]$Guard) {
    try {
        Save-PCCpuTrial $Report $Folder
        for($index=1;$index -le 3;$index++){
            if($Guard){& $Guard}
            [pscustomobject]@{Kind='CpuStatus';Value="$($Report.Mode) run $index of 3 - checking conditions"}
            $before=Get-PCCpuTuningContext
            if(@($Report.BeforeRuns).Count){Assert-PCCpuContextMatch $Report.BeforeRuns[0].ContextBefore $before}
            $run=$null
            Invoke-PCSensorSession -WithLoad -DurationSeconds 60 -Guard $Guard|ForEach-Object{
                if($_.Kind -eq 'Result'){$run=$_.Value}
                elseif($_.Kind -eq 'Progress'){[pscustomobject]@{Kind='Progress';Value=((($index-1)*100+$_.Value)/3)}}
                elseif($_.Kind -eq 'Frame'){$_}
            }
            if(-not $run){throw 'CPU workload returned no result.'}
            $temps=@($run.Frames|Select-Object -First 70|Select-Object Timestamp,CPUCelsius,QuerySeconds,Issue)
            $run.Frames=$temps
            $run|Add-Member NoteProperty RunIndex $index
            $run|Add-Member NoteProperty StartCPU $temps[0].CPUCelsius
            $run|Add-Member NoteProperty TemperatureSamples @($temps|Where-Object{-not (Get-PCStopReason $_)}).Count
            $run|Add-Member NoteProperty ContextBefore $before
            $run|Add-Member NoteProperty ContextAfter $null
            if($Report.Mode -eq 'Baseline'){$Report.BeforeRuns=@($Report.BeforeRuns)+@($run)}else{$Report.AfterRuns=@($Report.AfterRuns)+@($run)}
            # Save the returned measurement even if the following context query fails.
            Save-PCCpuTrial $Report $Folder
            if($Guard){& $Guard}
            $run.ContextAfter=Get-PCCpuTuningContext
            Save-PCCpuTrial $Report $Folder
            Assert-PCCpuRun $run $Report.BeforeRuns[0]
            if($index -lt 3){
                [pscustomobject]@{Kind='CpuStatus';Value='Run complete - 10-second cooldown (equal temperature is not guaranteed)'}
                for($pause=0;$pause -lt 10;$pause++){
                    if($Guard){& $Guard};Start-Sleep -Seconds 1
                    $frame=Get-PCSensorFrame;$reason=Get-PCStopReason $frame
                    [pscustomobject]@{Kind='Frame';Value=$frame}
                    if($reason){throw $reason}
                }
            }
        }
        $Report.State=if($Report.Mode -eq 'Baseline'){'Ready'}else{'Completed'}
        $Report.Message=if($Report.Mode -eq 'Baseline'){'Baseline saved. Record any external settings change before retesting; this app does not apply or restore CPU settings.'}else{'Retest saved. Review the measured comparison and restore external settings yourself if needed.'}
        if($Report.Mode -eq 'Baseline' -and (Get-PCCpuBatchSummary $Report.BeforeRuns).SpreadPercent -gt 5){$Report.Message='Baseline saved, but variability exceeds 5%. Retesting is disabled; collect a more repeatable baseline.'}
    }catch{$Report.State='Stopped';$Report.Message=$_.Exception.Message}
    Save-PCCpuTrial $Report $Folder
    [pscustomobject]@{Kind='CpuReport';Value=$Report}
}
function Format-PCCpuTrial($Report) {
    if(-not $Report){return 'Select a saved experiment or collect a baseline. Results survive app restarts and reboots.'}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.Add("$($Report.State) | $($Report.Message)")
    $lines.Add("Baseline settings (user reported): $($Report.BaselineNote)")
    if($Report.ChangeNote){$lines.Add("Retest change (user reported): $($Report.ChangeNote)")}
    if(@($Report.BeforeRuns).Count){$c=$Report.BeforeRuns[0].ContextBefore;$lines.Add("$($c.CPU) | $($c.Board) | BIOS $($c.BIOS)`nMemory: $($c.Memory)`nWindows $($c.OS) | Runtime $($c.Runtime) | Plan $($c.Plan)")}
    foreach($side in 'Before','After'){
        foreach($run in @($Report.($side+'Runs'))){
            $lines.Add(('{0} #{1}: {2} MiB/s | {3:N1} s | start {4} C / peak {5} C | {6}' -f $side,$run.RunIndex,$run.MiBPerSecond,$run.Seconds,$run.StartCPU,$run.PeakCPU,$run.StopReason))
        }
        try{$s=Get-PCCpuBatchSummary $Report.($side+'Runs');$lines.Add(('{0} median {1:N2} MiB/s | range {2:N2}-{3:N2} | spread {4:N2}%' -f $side,$s.Median,$s.Min,$s.Max,$s.SpreadPercent))}catch{}
    }
    $compare=Compare-PCCpuTrial $Report
    $lines.Add('Comparison: '+$compare.Verdict)
    if($null -ne $compare.ChangePercent){$lines.Add(('Median change: {0:+0.00;-0.00;0.00}% | median sampled peaks: {1:N1} -> {2:N1} C' -f $compare.ChangePercent,$compare.Before.PeakCPU,$compare.After.PeakCPU))}
    foreach($reason in $compare.Reasons){$lines.Add($reason)}
    $lines.Add('Three runs and non-overlapping ranges do not establish statistical significance, stability, or that the CPU change caused the difference.')
    $lines.Add($Report.Limitations)
    $lines -join "`n`n"
}
