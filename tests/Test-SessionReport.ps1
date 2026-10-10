$ErrorActionPreference='Stop'
foreach($module in 'Results','SessionExport','SessionDetails','ComparisonReport','SessionReport'){. "$PSScriptRoot/../$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
$session=[pscustomobject]@{Test='GPU-endurance-300s-v1';Timestamp='2026-10-10T12:00:00Z';GPUName='GPU <example>';CPUName='CPU & name';Note='<script>alert(1)</script>';Completed=$false;Seconds=20;RequestedSeconds=300;StopReason='User';EnduranceOutcome='Stopped by user';Frames=@(
    [pscustomobject]@{Sensors=@([pscustomobject]@{Parent='/gpu/0';Identifier='gpu/temp';Name='GPU Core';HardwareName='GPU <example>';Type='Temperature';Value=40})},
    [pscustomobject]@{Issue='Sensor failure';Sensors=@([pscustomobject]@{Parent='/gpu/0';Identifier='gpu/temp';Name='GPU Core';HardwareName='GPU <example>';Type='Temperature';Value=99})}
);ReliabilityEvidence=$null}
$html=ConvertTo-PCSessionHtml $session @() '0.31.0'
Assert ($html -match 'Stopped by user' -and $html -match 'not collected') 'Stop or legacy evidence status missing'
Assert ($html -match '40.0' -and $html -match '1/2 \(50%\)' -and $html -notmatch '>99.0<') 'Report disagrees with sensor coverage or includes failed readings'
Assert ($html -notmatch '<script' -and $html -match '&lt;script&gt;' -and $html -match 'GPU &lt;example&gt;' -and $html -match 'CPU &amp; name') 'Report allows unescaped saved data'
Assert ($html -match "default-src 'none'" -and $html -notmatch '(?i)<(script|iframe|form)|src=|href=') 'Offline report includes active/external content'
$empty=ConvertTo-PCSessionHtml ([pscustomobject]@{Test='Sensors-only-v1';Frames=@()}) @() 'test'
Assert ($empty -match 'No retained sensor readings' -and $empty -match 'No note saved' -and $empty -match 'completion not supplied') 'Missing data not explained'
$path=Join-Path ([IO.Path]::GetTempPath()) ('pc-report-'+[guid]::NewGuid()+'.html')
try{
    Save-PCSessionHtml $session @() '0.31.0' $path
    Assert (([IO.File]::ReadAllText($path)) -eq $html) 'Saved report differs from rendered report'
    $session.Note='Replacement note';Save-PCSessionHtml $session @() '0.31.0' $path
    Assert (([IO.File]::ReadAllText($path)) -match 'Replacement note') 'Existing report replacement failed'
    $before=[IO.File]::ReadAllText($path);$failed=$false
    try{Save-PCSessionHtml $null @() 'test' $path}catch{$failed=$true}
    Assert ($failed -and [IO.File]::ReadAllText($path) -eq $before) 'Invalid report truncated existing file'
}finally{if(Test-Path $path){Remove-Item $path}}
'PASS: readable single-session report, stopped/legacy evidence, failed-sample exclusion, coverage, HTML encoding, offline content, atomic replacement and failure preservation'
