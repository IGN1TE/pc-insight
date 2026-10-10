# Offline report using the same summary and sensor calculations as Test results.
function ConvertTo-PCSessionHtml($Session,$History=@(),[string]$Version='') {
    if(-not $Session -or -not $Session.Test){throw 'Choose a saved session first.'}
    $summary=ConvertTo-PCReportHtmlText (Get-PCSessionSummary $Session $History)
    $recorded=ConvertTo-PCReportHtmlText $Session.Timestamp
    $test=ConvertTo-PCReportHtmlText $Session.Test
    $note=if([string]::IsNullOrWhiteSpace([string]$Session.Note)){'No note saved.'}else{ConvertTo-PCReportHtmlText $Session.Note}
    $appVersion=ConvertTo-PCReportHtmlText $Version
    $details=@(Get-PCSessionSensorDetails $Session)
    $rows=[Text.StringBuilder]::new()
    foreach($sensor in $details){
        $null=$rows.Append('<tr>')
        foreach($field in 'Device','Sensor','Type','MinText','AverageText','MaxText','Unit','Coverage'){
            $null=$rows.Append('<td>').Append((ConvertTo-PCReportHtmlText $sensor.$field)).Append('</td>')
        }
        $null=$rows.Append('</tr>')
    }
    $sensorSection=if($details.Count){'<div class="scroll"><table><caption>Only retained readings are available. Failed frames and duplicate sensor readings within a frame are excluded. Averages are sample means, not time-weighted.</caption><thead><tr><th scope="col">Device</th><th scope="col">Sensor</th><th scope="col">Type</th><th scope="col">Minimum</th><th scope="col">Average</th><th scope="col">Peak</th><th scope="col">Unit</th><th scope="col">Coverage</th></tr></thead><tbody>'+$rows.ToString()+'</tbody></table></div>'}else{'<p>No retained sensor readings are available for this session. Missing readings are not zero.</p>'}
    $metadata=[Text.StringBuilder]::new()
    $labels=[ordered]@{CPUName='CPU';GPUName='GPU';Renderer='GPU renderer';DriverVersion='GPU driver';MemoryConfig='Memory configuration';Plan='Power plan'}
    foreach($field in $labels.Keys){
        if(-not [string]::IsNullOrWhiteSpace([string]$Session.$field)){
            $null=$metadata.Append('<dt>').Append($labels[$field]).Append('</dt><dd>').Append((ConvertTo-PCReportHtmlText $Session.$field)).Append('</dd>')
        }
    }
    $context=if($metadata.Length){'<dl>'+$metadata.ToString()+'</dl>'}else{'<p>Hardware and settings metadata were not recorded.</p>'}
    @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>PC Insight - Saved result</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f2f3f8;color:#202235;font:15px/1.55 'Segoe UI',Arial,sans-serif}main{max-width:1180px;margin:30px auto;padding:0 24px}header{padding:28px 32px;background:#211b38;color:#fff;border-top:5px solid #9b79ef;border-radius:12px}.brand{color:#c1acf4;font-size:13px;font-weight:700;letter-spacing:.12em}h1{font-size:30px;margin:8px 0;line-height:1.25}header p{margin:6px 0;color:#dbd3ee}.stamp{font-size:13px;overflow-wrap:anywhere}section{margin-top:20px;padding:24px;background:#fff;border:1px solid #dfe0eb;border-radius:12px}h2{font-size:20px;margin:0 0 12px}pre{font:inherit;white-space:pre-wrap;overflow-wrap:anywhere;margin:0}.note{border-left:4px solid #8860d4;white-space:pre-wrap;overflow-wrap:anywhere}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}caption{text-align:left;color:#62667c;margin-bottom:14px}th,td{padding:10px;text-align:left;border-bottom:1px solid #e2e3ec;vertical-align:top;overflow-wrap:anywhere}thead th{background:#eee9f8;color:#40325e}tbody tr:nth-child(even){background:#f8f8fb}dt{font-weight:600;color:#40325e;margin-top:10px}dd{margin-left:0;overflow-wrap:anywhere}footer{padding:24px 0;font-size:12px;color:#62667c}p{margin:8px 0}
@media(max-width:650px){main{margin:12px auto;padding:0 10px}header,section{padding:18px}h1{font-size:26px}table{min-width:750px}}
@media print{@page{size:landscape;margin:14mm}body{background:#fff;font-size:11px}main{max-width:none;margin:0;padding:0}header{background:#fff;color:#202235;border:0;border-bottom:2px solid #8860d4;border-radius:0;padding:10px 0}header p,.brand{color:#40325e}section{padding:16px 0;border:0;border-radius:0}h2{break-after:avoid}table{font-size:10px;min-width:0}thead{display:table-header-group}tr{break-inside:avoid}.scroll{overflow:visible}th,td{padding:6px}.note{border:0}footer{padding-bottom:0}}
</style></head><body><main>
<header><div class="brand">PC INSIGHT</div><h1>Saved test result</h1><p class="stamp">$recorded</p><p class="stamp">$test</p><p class="stamp">Exported with PC Insight $appVersion</p></header>
<section class="note"><h2>Your note</h2><p>$note</p></section>
<section><h2>Session summary</h2><pre>$summary</pre></section>
<section><h2>Retained sensor measurements</h2>$sensorSection</section>
<section><h2>Recorded context</h2>$context</section>
<footer>Local saved-data report. Use your browser's Print command to print or save as PDF. Sampled readings, missing event evidence, and a completed test do not establish stability or tuning headroom. Hardware details and your note may be present; review before sharing. Raw readings remain available through CSV or JSON export.</footer>
</main></body></html>
"@
}
function Save-PCSessionHtml($Session,$History,[string]$Version,[string]$Path) {
    $html=ConvertTo-PCSessionHtml $Session $History $Version
    $fullPath=[IO.Path]::GetFullPath($Path)
    $temporary=Join-Path ([IO.Path]::GetDirectoryName($fullPath)) ([IO.Path]::GetRandomFileName())
    try{
        [IO.File]::WriteAllText($temporary,$html,[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($fullPath)){[IO.File]::Replace($temporary,$fullPath,[NullString]::Value)}
        else{[IO.File]::Move($temporary,$fullPath)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
