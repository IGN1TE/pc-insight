# Compact, bounded copies of readings already collected by the GPU workload.
# This module does not query sensors, run workloads or change hardware settings.
. (Join-Path $PSScriptRoot 'SessionExport.ps1')
. (Join-Path $PSScriptRoot 'SessionChart.ps1')
function Get-PCTrialSensorKey($Sensor) {
    ConvertTo-Json -Compress -InputObject @([string]$Sensor.Parent,[string]$Sensor.Identifier,[string]$Sensor.HardwareName,[string]$Sensor.Name,[string]$Sensor.Type)
}
function ConvertTo-PCTrialSensorValue($Value,[string]$Type) {
    if($Value -is [bool]){return $null}
    $text=ConvertTo-PCInvariantNumber $Value
    if($text -eq ''){return $null}
    $number=[double]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)
    # Bound imported values before plotting. Zero is a real reading, not missing.
    if([math]::Abs($number) -gt 1000000000 -or ($Type -eq 'Load' -and ($number -lt 0 -or $number -gt 100))){return $null}
    $number
}
function ConvertTo-PCClockTrialTelemetry($Result) {
    $telemetry=[pscustomobject]@{
        Schema=1;Kind='PCInsight.GpuTrialTelemetry';GPUName=[string]$Result.GPUName
        Channels=@();Samples=@();SourceFrames=@($Result.Frames|Where-Object {$null -ne $_}).Count;Truncated=$false;Notes=@()
    }
    try{
        $frames=@($Result.Frames|Where-Object {$null -ne $_}|Select-Object -First 64)
        $telemetry.Truncated=$telemetry.SourceFrames -gt $frames.Count
        $channels=@{};$parents=@{}
        foreach($frame in $frames){
            foreach($sensor in @($frame.Sensors)){
                if($sensor.Parent -notmatch '^/gpu[^/]*/' -or $sensor.HardwareName -ne $Result.GPUName -or
                    $sensor.Type -notin @('Temperature','Clock','Power','Load') -or
                    [string]::IsNullOrWhiteSpace($sensor.Identifier) -or [string]::IsNullOrWhiteSpace($sensor.Name)){continue}
                if(([string]$sensor.Identifier).Length -gt 256 -or ([string]$sensor.Name).Length -gt 128 -or
                    ([string]$sensor.Parent).Length -gt 128 -or ([string]$sensor.HardwareName).Length -gt 256){continue}
                $parents[[string]$sensor.Parent]=$true
                $key=Get-PCTrialSensorKey $sensor
                if(-not $channels.ContainsKey($key)){
                    $channels[$key]=[pscustomobject]@{IdentityKey=$key;Parent=[string]$sensor.Parent;Identifier=[string]$sensor.Identifier;HardwareName=[string]$sensor.HardwareName;Name=[string]$sensor.Name;Type=[string]$sensor.Type}
                }
            }
        }
        if($parents.Count -gt 1){throw 'Multiple sensor devices match this GPU name; telemetry was not combined.'}
        $telemetry.Channels=@($channels.Values|Sort-Object @{Expression={if($_.Type -eq 'Temperature' -and $_.Name -eq 'GPU Core'){0}else{1}}},Type,Name,Identifier|Select-Object -First 16)
        if($channels.Count -gt 16){$telemetry.Truncated=$true}
        $samples=[Collections.Generic.List[object]]::new()
        foreach($frame in $frames){
            $issue=[string]$frame.Issue
            $queryText=ConvertTo-PCInvariantNumber $frame.QuerySeconds
            if($queryText -eq '' -or [double]::Parse($queryText,[Globalization.CultureInfo]::InvariantCulture) -lt 0 -or
                [double]::Parse($queryText,[Globalization.CultureInfo]::InvariantCulture) -gt 3){$issue='Sensor query duration missing, invalid or over 3 seconds.'}
            if($issue.Length -gt 256){$issue=$issue.Substring(0,256)}
            $byKey=@{}
            foreach($sensor in @($frame.Sensors)){
                $key=Get-PCTrialSensorKey $sensor
                if($byKey.ContainsKey($key)){$byKey[$key]=$null}else{$byKey[$key]=$sensor}
            }
            $values=@(foreach($channel in $telemetry.Channels){
                $sensor=$byKey[$channel.IdentityKey]
                if($issue -or -not $sensor){$null}else{ConvertTo-PCTrialSensorValue $sensor.Value $channel.Type}
            })
            $timestamp=[string]$frame.Timestamp;if($timestamp.Length -gt 64){$timestamp=''}
            $samples.Add([pscustomobject]@{Timestamp=$timestamp;Issue=$issue;Values=$values})
        }
        $telemetry.Samples=@($samples.ToArray())
        if(-not $telemetry.Channels.Count){$telemetry.Notes+= 'No identified GPU sensor channels were retained for this run.'}
        if($telemetry.Truncated){$telemetry.Notes+= 'Telemetry is bounded to the first 64 frames and 16 sensor channels; additional data was omitted.'}
    }catch{
        $telemetry.Channels=@();$telemetry.Samples=@();$telemetry.Notes=@('Telemetry unavailable: '+$_.Exception.Message)
    }
    $telemetry
}
function Get-PCClockTrialTelemetryRuns($Report) {
    if(-not $Report -or $Report.Schema -ne 2){return}
    foreach($side in 'Before','After'){
        $label=if($side -eq 'Before'){'Baseline'}else{'Retest'}
        foreach($run in @($Report.($side+'Runs')|Select-Object -First 3)){
            if(-not $run){continue}
            $state=if($run.Eligible -eq $true){'eligible'}else{'excluded'}
            [pscustomobject]@{Key=($side+':'+$run.RunIndex);Label="$label $($run.RunIndex) | $state";Run=$run}
        }
    }
}
function Get-PCClockTrialTelemetryChannels($Run) {
    $t=$Run.Telemetry
    if(-not $t -or $t.Kind -ne 'PCInsight.GpuTrialTelemetry' -or $t.Schema -ne 1 -or $t.GPUName -ne $Run.GPUName){return}
    $seen=@{};$index=0
    foreach($channel in @($t.Channels|Select-Object -First 16)){
        $key=Get-PCTrialSensorKey $channel
        if($channel.Type -in @('Temperature','Clock','Power','Load') -and $channel.Parent -match '^/gpu[^/]*/' -and
            $channel.HardwareName -eq $Run.GPUName -and $channel.Identifier -and $channel.Name -and
            $channel.IdentityKey -eq $key -and -not $seen.ContainsKey($key)){
            $seen[$key]=$true
            $type=if($channel.Type -eq 'Temperature' -and $channel.Name -match '(?i)headroom|distance|tjmax'){'Temperature headroom'}else{$channel.Type}
            $unit=Get-PCSensorUnit $channel.Type
            [pscustomobject]@{Index=$index;IdentityKey=$key;Name=$channel.Name;Type=$channel.Type;Unit=$unit;Label="$($channel.Name) | $type ($unit) | $($channel.Identifier)"}
        }
        $index++
    }
}
function Get-PCClockTrialTelemetryView($Run,$Channel) {
    $empty=[pscustomobject]@{Plot=$null;Summary='No valid timestamped readings for this sensor.';Notes=''}
    if(-not $Run -or -not $Channel){return $empty}
    $valid=@(Get-PCClockTrialTelemetryChannels $Run|Where-Object {$_.Index -eq $Channel.Index -and $_.IdentityKey -eq $Channel.IdentityKey})
    if($valid.Count -ne 1){return $empty}
    $first=$null;$previous=$null
    $series=@(foreach($sample in @($Run.Telemetry.Samples|Select-Object -First 64)){
        $timestamp=[datetimeoffset]::MinValue
        $timeOK=[datetimeoffset]::TryParse([string]$sample.Timestamp,[ref]$timestamp)
        if($timeOK -and $null -eq $first){$first=$timestamp}
        $ordered=$timeOK -and ($null -eq $previous -or $timestamp -gt $previous)
        if($ordered){$previous=$timestamp}
        $value=$null
        if($ordered -and -not $sample.Issue -and $sample.Values -is [array] -and @($sample.Values).Count -eq @($Run.Telemetry.Channels).Count){
            $value=ConvertTo-PCTrialSensorValue $sample.Values[$Channel.Index] $Channel.Type
        }
        [pscustomobject]@{Timestamp=[string]$sample.Timestamp;Seconds=if($ordered){($timestamp-$first).TotalSeconds}else{$null};Value=$value}
    })
    $plot=Get-PCSessionPlot $series
    if($plot){
        $stats=$plot.Points|Measure-Object Value -Minimum -Maximum -Average
        $empty.Plot=$plot
        $empty.Summary=('{0}/{1} readings plotted | min {2:N1}, mean {3:N1}, max {4:N1} {5}. Mean is a sample average.' -f $plot.Samples,$plot.RetainedFrames,$stats.Minimum,$stats.Average,$stats.Maximum,$Channel.Unit)
    }
    $empty.Notes=(@($Run.Telemetry.Notes) -join ' ')
    $empty
}
