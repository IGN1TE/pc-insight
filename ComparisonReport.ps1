# Standalone, offline report from the existing comparison snapshot; no new calculations.
function ConvertTo-PCReportHtmlText($Value) {
    if($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)){return 'Unavailable'}
    [Net.WebUtility]::HtmlEncode([string]$Value)
}
function ConvertTo-PCComparisonHtml($Comparison) {
    if(-not $Comparison -or $Comparison.Kind -ne 'PCInsight.SessionComparison'){throw 'Choose a saved-session comparison first.'}
    $rows=[Text.StringBuilder]::new()
    foreach($row in @($Comparison.Rows)){
        $null=$rows.Append('<tr>')
        foreach($field in 'Metric','BeforeText','AfterText','ChangeText','Coverage'){
            $value=if($field -eq 'Coverage' -and [string]::IsNullOrWhiteSpace([string]$row.$field)){'Not applicable'}else{$row.$field}
            $null=$rows.Append('<td>').Append((ConvertTo-PCReportHtmlText $value)).Append('</td>')
        }
        $null=$rows.Append('</tr>')
    }
    $metadata=[Text.StringBuilder]::new()
    $fields=[ordered]@{Timestamp='Recorded';Test='Test';CPUName='CPU';Renderer='GPU renderer';DriverVersion='GPU driver';Runtime='Runtime';Workers='Workers';MemoryConfig='Memory configuration';BufferMiB='RAM buffer (MiB)';WarmupSeconds='Warm-up (seconds)';Plan='Power plan';Seconds='Duration (seconds)';Completed='Completed';StopReason='Stop reason'}
    foreach($field in $fields.Keys){
        $a=$Comparison.Before.$field;$b=$Comparison.After.$field
        if($null -eq $a -and $null -eq $b){continue}
        $null=$metadata.Append('<tr><th scope="row">').Append($fields[$field]).Append('</th><td>').Append((ConvertTo-PCReportHtmlText $a)).Append('</td><td>').Append((ConvertTo-PCReportHtmlText $b)).Append('</td></tr>')
    }
    $notes=[Text.StringBuilder]::new()
    foreach($note in @($Comparison.Notes)){$null=$notes.Append('<li>').Append((ConvertTo-PCReportHtmlText $note)).Append('</li>')}
    $reasons=[Text.StringBuilder]::new()
    foreach($reason in @($Comparison.Reasons)){$null=$reasons.Append('<li>').Append((ConvertTo-PCReportHtmlText $reason)).Append('</li>')}
    $status=ConvertTo-PCReportHtmlText $Comparison.Status
    $created=ConvertTo-PCReportHtmlText $Comparison.Created
    $reasonSection=if($reasons.Length){'<ul>'+ $reasons.ToString()+'</ul>'}else{''}
    @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>PC Insight - Session comparison</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f2f3f8;color:#202235;font:15px/1.55 'Segoe UI',Arial,sans-serif}main{max-width:1120px;margin:32px auto;padding:0 24px}header{background:#211b38;color:#fff;padding:30px 32px;border-top:5px solid #9b79ef;border-radius:12px}.brand{color:#c1acf4;font-weight:700;letter-spacing:.12em;font-size:13px}h1{font-size:30px;line-height:1.2;margin:10px 0}header p{margin:8px 0;color:#dbd3ee}.stamp{font-size:12px;overflow-wrap:anywhere}section{margin-top:22px;padding:24px;background:white;border:1px solid #dfe0eb;border-radius:12px}h2{font-size:19px;margin:0 0 14px}.status{border-left:4px solid #8860d4}p{margin:8px 0}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:12px 10px;text-align:left;border-bottom:1px solid #e2e3ec;vertical-align:top;overflow-wrap:anywhere}thead th{background:#eee9f8;color:#40325e;font-size:12px}tbody tr:nth-child(even){background:#f8f8fb}td:first-child{min-width:150px}th{font-weight:600}li{margin:8px 0}ul{padding-left:22px}footer{font-size:12px;color:#62667c;padding:22px 0 32px}.muted{color:#62667c}caption{text-align:left;margin-bottom:10px;color:#62667c;font-size:13px}
@media(max-width:600px){main{margin:12px auto;padding:0 10px}header,section{padding:18px}h1{font-size:25px}table{min-width:580px}}
@media print{@page{size:landscape;margin:14mm}body{background:white;font-size:11px}main{max-width:none;margin:0;padding:0}header{background:white;color:#202235;border-radius:0;padding:8px 0 14px}header p,.brand{color:#40325e}section{padding:14px 0;border:0;border-radius:0}h1{font-size:24px}h2{break-after:avoid}table{font-size:10px;min-width:0}thead{display:table-header-group}tr{break-inside:avoid}.scroll{overflow:visible}th,td{padding:7px}footer{padding-bottom:0}}
</style></head><body><main>
<header><div class="brand">PC INSIGHT</div><h1>Saved-session comparison</h1><p>Reference A and selected session B</p><p class="stamp">Comparison created: $created</p></header>
<section class="status"><h2>Comparison status</h2><p>$status</p>$reasonSection<p class="muted">Changes are B minus A. A higher number is not automatically better.</p></section>
<section><h2>Measurements</h2><div class="scroll"><table><caption>Values and comparison decisions match the saved comparison. Unavailable readings remain unavailable.</caption><thead><tr><th scope="col">Measurement</th><th scope="col">Reference A</th><th scope="col">Session B</th><th scope="col">Change</th><th scope="col">Sample coverage</th></tr></thead><tbody>$rows</tbody></table></div></section>
<section><h2>Session details</h2><div class="scroll"><table><thead><tr><th scope="col">Detail</th><th scope="col">Reference A</th><th scope="col">Session B</th></tr></thead><tbody>$metadata</tbody></table></div></section>
<section><h2>Conditions and limits</h2><ul>$notes</ul></section>
<footer>PC Insight &middot; Local saved-data report. Use your browser's Print command to print or save as PDF. Hardware details and recorded settings may be present; review before sharing.</footer>
</main></body></html>
"@
}
function Save-PCComparisonHtml($Comparison,[string]$Path) {
    $html=ConvertTo-PCComparisonHtml $Comparison
    # Stage in the destination directory so a failed write does not truncate an existing report.
    $fullPath=[IO.Path]::GetFullPath($Path)
    $temporary=Join-Path ([IO.Path]::GetDirectoryName($fullPath)) ([IO.Path]::GetRandomFileName())
    try{
        [IO.File]::WriteAllText($temporary,$html,[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($fullPath)){[IO.File]::Replace($temporary,$fullPath,[NullString]::Value)}
        else{[IO.File]::Move($temporary,$fullPath)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
