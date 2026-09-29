function ConvertTo-PCSafeCsvText($Value) {
    $text=[string]$Value
    # CSV quoting alone does not prevent spreadsheet formula execution.
    if($text -match '^\s*[=+@-]' -or $text -match '^[\t\r\n]'){return "'"+$text}
    return $text
}
function ConvertTo-PCInvariantNumber($Value) {
    if($null -eq $Value -or [string]$Value -eq ''){return ''}
    $number=0.0
    if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){
        if($Value -is [ValueType]){$number=[double]$Value}else{return ''}
    }
    if([double]::IsNaN($number) -or [double]::IsInfinity($number)){return ''}
    return $number.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
}
function Get-PCSensorUnit([string]$Type) {
    switch($Type){
        'Temperature'{'C'} 'Load'{'%'} 'Power'{'W'} 'Clock'{'MHz'}
        'Voltage'{'V'} 'Current'{'A'} 'Fan'{'RPM'} 'Data'{'GB'}
        'SmallData'{'MB'} 'Throughput'{'B/s'} default{''}
    }
}
function Get-PCSessionExportRows($Session) {
    $frames=@($Session.Frames|Where-Object{$null -ne $_})
    if(-not $frames.Count){throw 'This session has no retained sensor samples to export.'}
    $index=0
    foreach($frame in $frames){
        $index++
        $sensors=@($frame.Sensors|Where-Object{$null -ne $_})
        if(-not $sensors.Count){$sensors=@($null)}
        foreach($sensor in $sensors){
            [pscustomobject][ordered]@{
                SessionTimestamp=ConvertTo-PCSafeCsvText $Session.Timestamp
                Test=ConvertTo-PCSafeCsvText $Session.Test
                Completed=if($null -eq $Session.Completed){''}else{[string]$Session.Completed}
                StopReason=ConvertTo-PCSafeCsvText $Session.StopReason
                RetainedFrames=$frames.Count
                TotalQueries=ConvertTo-PCInvariantNumber $Session.TotalQueries
                FrameIndex=$index
                SampleTimestamp=ConvertTo-PCSafeCsvText $frame.Timestamp
                Provider=ConvertTo-PCSafeCsvText $frame.Provider
                Issue=ConvertTo-PCSafeCsvText $frame.Issue
                CPUCelsius=ConvertTo-PCInvariantNumber $frame.CPUCelsius
                RAMUsedPercent=ConvertTo-PCInvariantNumber $frame.MemoryUsedPercent
                Hardware=ConvertTo-PCSafeCsvText $sensor.HardwareName
                Parent=ConvertTo-PCSafeCsvText $sensor.Parent
                Identifier=ConvertTo-PCSafeCsvText $sensor.Identifier
                SensorName=ConvertTo-PCSafeCsvText $sensor.Name
                SensorType=ConvertTo-PCSafeCsvText $sensor.Type
                Unit=Get-PCSensorUnit $sensor.Type
                Value=ConvertTo-PCInvariantNumber $sensor.Value
            }
        }
    }
}
function Export-PCSessionCsv($Session,[string]$Path) {
    $rows=@(Get-PCSessionExportRows $Session)
    $full=[IO.Path]::GetFullPath($Path)
    $temporary=Join-Path (Split-Path $full) ([IO.Path]::GetRandomFileName())
    try {
        $lines=@($rows|ConvertTo-Csv -NoTypeInformation)
        [IO.File]::WriteAllLines($temporary,[string[]]$lines,[Text.UTF8Encoding]::new($true))
        if([IO.File]::Exists($full)){[IO.File]::Replace($temporary,$full,[NullString]::Value)}else{[IO.File]::Move($temporary,$full)}
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
    return $rows.Count
}
