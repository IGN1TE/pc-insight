function Get-PCSessionSensorSeries($Session,$Detail) {
    if(-not $Detail){return}
    $first=$null;$previous=$null
    foreach($frame in @($Session.Frames|Where-Object{$null -ne $_})){
        $timestamp=[datetimeoffset]::MinValue
        $timeOK=[datetimeoffset]::TryParse([string]$frame.Timestamp,[ref]$timestamp)
        if($timeOK -and $null -eq $first){$first=$timestamp}
        $ordered=$timeOK -and ($null -eq $previous -or $timestamp -gt $previous)
        if($ordered){$previous=$timestamp}
        $value=$null
        if(-not $frame.Issue -and $ordered){
            $sensors=@($frame.Sensors|Where-Object{$null -ne $_})
            if($null -ne $frame.MemoryUsedPercent){$sensors += [pscustomobject]@{Parent='memory';Identifier='pcinsight/memory/used';HardwareName='System memory';Name='Memory used';Type='Load';Value=$frame.MemoryUsedPercent}}
            foreach($sensor in $sensors){
                $key=ConvertTo-Json -Compress -InputObject @([string]$sensor.Parent,[string]$sensor.Identifier,[string]$sensor.HardwareName,[string]$sensor.Name,[string]$sensor.Type)
                if($key -ne $Detail.IdentityKey){continue}
                $text=ConvertTo-PCInvariantNumber $sensor.Value
                if($text -eq ''){continue}
                $value=[double]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)
                break
            }
        }
        [pscustomobject]@{
            Timestamp=[string]$frame.Timestamp
            Seconds=if($ordered -and $null -ne $first){($timestamp-$first).TotalSeconds}else{$null}
            Value=$value
        }
    }
}
function Get-PCSessionPlot($Series) {
    $rows=@($Series)
    $valid=@($rows|Where-Object{$null -ne $_.Value -and $null -ne $_.Seconds})
    if(-not $valid.Count){return $null}
    $times=@($rows|Where-Object{$null -ne $_.Seconds})
    $maxSeconds=[double]($times|Measure-Object Seconds -Maximum).Maximum
    $span=[math]::Max(1,$maxSeconds)
    $stats=$valid|Measure-Object Value -Minimum -Maximum
    $lower=[double]$stats.Minimum;$upper=[double]$stats.Maximum
    if($lower -eq $upper){$padding=[math]::Max(1,[math]::Abs($lower)*0.05);$lower-=$padding;$upper+=$padding}
    $deltas=@()
    for($i=1;$i -lt $times.Count;$i++){
        $delta=$times[$i].Seconds-$times[$i-1].Seconds
        if($delta -gt 0){$deltas+=$delta}
    }
    $threshold=3.0
    if($deltas.Count){$sorted=@($deltas|Sort-Object);$threshold=[math]::Max(3,3*$sorted[[int][math]::Floor(($sorted.Count-1)/2)])}
    $points=@();$break=$true;$previous=$null
    foreach($row in $rows){
        if($null -eq $row.Value -or $null -eq $row.Seconds){$break=$true;continue}
        if($null -ne $previous -and $row.Seconds-$previous -gt $threshold){$break=$true}
        $points += [pscustomobject]@{X=8+784*$row.Seconds/$span;Y=8+134*(1-($row.Value-$lower)/($upper-$lower));BreakBefore=$break;Value=$row.Value;Timestamp=$row.Timestamp}
        $break=$false;$previous=$row.Seconds
    }
    [pscustomobject]@{Points=$points;Minimum=$lower;Maximum=$upper;Seconds=$maxSeconds;Samples=$valid.Count;RetainedFrames=$rows.Count}
}
