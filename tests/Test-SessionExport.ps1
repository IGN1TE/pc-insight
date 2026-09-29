$ErrorActionPreference='Stop'
. "$PSScriptRoot/../SessionExport.ps1"
function Assert($condition,$message){if(-not $condition){throw $message}}
$session=[pscustomobject]@{Timestamp='2026-09-29T00:00:00Z';Test='Continuous-monitor-v1';Completed=$true;TotalQueries=401;Frames=@(
 [pscustomobject]@{Timestamp='2026-09-29T00:00:01Z';CPUCelsius=35.5;MemoryUsedPercent=0;Sensors=@(
 [pscustomobject]@{Identifier='/gpu-nvidia/0/load/0';Parent='/gpu-nvidia/0';Name='GPU Core';HardwareName='GPU one';Type='Load';Value=0},
 [pscustomobject]@{Identifier='/gpu-nvidia/1/temperature/0';Parent='/gpu-nvidia/1';Name='=unsafe';HardwareName='GPU two';Type='Temperature';Value=51.25})},
 [pscustomobject]@{Timestamp='2026-09-29T00:00:02Z';CPUCelsius=$null;Sensors=@();Issue='Unavailable, "retry"'}
)}
$rows=@(Get-PCSessionExportRows $session)
Assert ($rows.Count -eq 3) 'Expected two sensor rows and one missing-data row'
Assert ($rows[0].Value -eq '0' -and $rows[0].RAMUsedPercent -eq '0') 'Zero lost'
Assert ($rows[2].Value -eq '' -and $rows[2].CPUCelsius -eq '') 'Missing values became zero'
Assert ($rows[0].Parent -ne $rows[1].Parent) 'Devices merged'
Assert ($rows[1].SensorName -eq "'=unsafe") 'Formula text not neutralized'
Assert ($rows[0].RetainedFrames -eq 2 -and $rows[0].TotalQueries -eq 401) 'Retention context incorrect'
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pc-export-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory $folder
try{
 $path=Join-Path $folder 'session.csv'
 $null=Export-PCSessionCsv $session $path
 $read=@(Import-Csv $path)
 Assert ($read.Count -eq 3 -and $read[2].Issue -eq 'Unavailable, "retry"') 'CSV quote roundtrip failed'
 $null=Export-PCSessionCsv $session $path
 Assert (@(Import-Csv $path).Count -eq 3) 'File replacement failed'
 $bytes=[IO.File]::ReadAllBytes($path)
 Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'Missing UTF8 BOM'
 $old=[Threading.Thread]::CurrentThread.CurrentCulture
 try{
  [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('fr-FR')
  Assert ((ConvertTo-PCInvariantNumber 51.25) -eq '51.25') 'Locale changed numeric output'
 }finally{[Threading.Thread]::CurrentThread.CurrentCulture=$old}
 $failed=$false;try{Export-PCSessionCsv ([pscustomobject]@{Frames=@()}) $path}catch{$failed=$true}
 Assert $failed 'Empty session exported'
 Assert (@(Import-Csv $path).Count -eq 3) 'Failed export damaged existing file'
 'PASS: missing readings, zero values, device identity, formulas, CSV quoting, BOM, overwrite, locale, failed export preservation'
}finally{Remove-Item $folder -Recurse -Force}
