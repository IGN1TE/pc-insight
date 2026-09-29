function Get-PCSessionSensorDetails($Session) {
    $frames=@($Session.Frames|Where-Object{$null -ne $_})
    if(-not $frames.Count){return}
    $groups=@{}
    foreach($frame in $frames){
        $seen=@{}
        $sensors=@($frame.Sensors|Where-Object{$null -ne $_})
        if($null -ne $frame.MemoryUsedPercent){
            $sensors+= [pscustomobject]@{Parent='memory';Identifier='pcinsight/memory/used';HardwareName='System memory';Name='Memory used';Type='Load';Value=$frame.MemoryUsedPercent}
        }
        foreach($sensor in $sensors){
            # JSON tuple avoids delimiter collisions and preserves device identity in old logs.
            $key=ConvertTo-Json -Compress -InputObject @([string]$sensor.Parent,[string]$sensor.Identifier,[string]$sensor.HardwareName,[string]$sensor.Name,[string]$sensor.Type)
            if(-not $groups.ContainsKey($key)){
                $groups[$key]=[pscustomobject]@{IdentityKey=$key;Device=if($sensor.HardwareName){[string]$sensor.HardwareName}else{[string]$sensor.Parent};Sensor=[string]$sensor.Name;Type=[string]$sensor.Type;Identifier=[string]$sensor.Identifier;Parent=[string]$sensor.Parent;Values=[Collections.Generic.List[double]]::new()}
            }
            if($frame.Issue -or $seen.ContainsKey($key)){continue}
            $text=ConvertTo-PCInvariantNumber $sensor.Value
            if($text -eq ''){continue}
            $seen[$key]=$true
            $groups[$key].Values.Add([double]::Parse($text,[Globalization.CultureInfo]::InvariantCulture))
        }
    }
    foreach($group in ($groups.Values|Sort-Object Device,Sensor,Identifier)){
        $values=@($group.Values)
        $minimum=$null;$average=$null;$maximum=$null
        if($values.Count){$stats=$values|Measure-Object -Minimum -Maximum -Average;$minimum=$stats.Minimum;$average=$stats.Average;$maximum=$stats.Maximum}
        $type=$group.Type
        if($type -eq 'Temperature' -and $group.Sensor -match '(?i)distance|tjmax|headroom'){$type='Temperature headroom'}
        [pscustomobject]@{
            IdentityKey=$group.IdentityKey;Device=$group.Device;Sensor=$group.Sensor;Type=$type
            Identifier=$group.Identifier;Parent=$group.Parent;Unit=Get-PCSensorUnit $group.Type
            Minimum=$minimum;Average=$average;Maximum=$maximum
            MinText=if($null -eq $minimum){'Unavailable'}else{'{0:N1}' -f $minimum}
            AverageText=if($null -eq $average){'Unavailable'}else{'{0:N1}' -f $average}
            MaxText=if($null -eq $maximum){'Unavailable'}else{'{0:N1}' -f $maximum}
            Samples=$values.Count;RetainedFrames=$frames.Count
            Coverage=('{0}/{1} ({2:N0}%)' -f $values.Count,$frames.Count,(100*$values.Count/$frames.Count))
        }
    }
}
