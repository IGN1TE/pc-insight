$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
foreach($module in 'Power','Results','SessionExport','SessionDetails','SessionComparison','ComparisonReport'){. "$root/$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Session($rate,$stamp){[pscustomobject]@{Test='SHA256-1MiB-parallel-v2';CPUName='CPU <test> & "name"';Workers=8;Runtime='4.0';Plan='balanced';Timestamp=$stamp;Completed=$true;MiBPerSecond=$rate;Seconds=20;Frames=@()}}
$a=Session 100 '2026-09-29T12:00:00Z';$b=Session 110 '2026-09-29T12:01:00Z'
$comparison=Get-PCSessionComparison $a $b
$html=ConvertTo-PCComparisonHtml $comparison
Assert ($html.Contains('CPU &lt;test&gt; &amp; &quot;name&quot;')) 'Hardware text was not HTML escaped'
foreach($row in $comparison.Rows){foreach($field in 'Metric','BeforeText','AfterText','ChangeText'){Assert ($html.Contains([Net.WebUtility]::HtmlEncode([string]$row.$field))) "Displayed comparison field was lost: $field"}}
Assert ($html.Contains('Benchmark throughput is not game FPS.')) 'Report omitted benchmark limitation'
Assert ($html -notmatch '<script|<iframe|<img|<link|https?://') 'Report unexpectedly depends on executable or external content'
$b.Workers=4
$blocked=Get-PCSessionComparison $a $b
$blocked.Notes+= '<script>alert("test")</script>'
$html=ConvertTo-PCComparisonHtml $blocked
Assert ($html.Contains('Workers differs.') -and $html.Contains('Not compared')) 'Blocked score comparison became a valid change'
Assert ($html.Contains('&lt;script&gt;') -and $html -notmatch '<script') 'Untrusted diagnostic text created HTML markup'
$missing=New-PCComparisonRow 'Missing temperature' $null 60 'C'
$blocked.Rows+= $missing
Assert ((ConvertTo-PCComparisonHtml $blocked).Contains('Unavailable')) 'Missing values were presented as measured zero'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('pc-report-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $dir
try{
    $path=Join-Path $dir 'report.html'
    Save-PCComparisonHtml $comparison $path
    Assert ((Get-Content $path -Raw).Contains('Saved-session comparison')) 'Report was not saved'
    Save-PCComparisonHtml $blocked $path
    Assert ((Get-Content $path -Raw).Contains('Workers differs.')) 'Existing report was not replaced'
    $prior=(Get-FileHash $path).Hash
    $threw=$false;try{Save-PCComparisonHtml ([pscustomobject]@{Kind='wrong'}) $path}catch{$threw=$true}
    Assert ($threw -and (Get-FileHash $path).Hash -eq $prior) 'Failed export damaged an existing report'
    Assert (@(Get-ChildItem $dir).Count -eq 1) 'Export left temporary files'
    # Exercise the real shared button handler with only the native picker stubbed.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'SessionComparisonUI.ps1'),[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'UI script did not parse'
    $f=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Export-PCSessionComparison'},$true)
    . ([scriptblock]::Create($f.Extent.Text))
    $script:sessionComparison=$comparison
    $script:ui=@{ComparisonExportStatus=[pscustomobject]@{Text=''}}
    $script:reportTestPath=$path
    function Show-Error($message){throw $message}
    function Select-PCComparisonExportPath($Format){
        Assert ($Format -eq 'html') 'Readable report requested the wrong file type'
        $script:sessionComparison.Before.CPUName='MUTATED DURING SAVE'
        return $script:reportTestPath
    }
    Export-PCSessionComparison 'html'
    $saved=Get-Content $path -Raw
    Assert ($saved.Contains('CPU &lt;test&gt;') -and -not $saved.Contains('MUTATED DURING SAVE')) 'Report changed while the Save dialog was open'
    function Select-PCComparisonExportPath($Format){return}
    $prior=(Get-FileHash $path).Hash
    Export-PCSessionComparison 'html'
    Assert ((Get-FileHash $path).Hash -eq $prior) 'Cancelling changed the report'
    $script:reportTestPath=Join-Path $dir 'comparison.json'
    function Select-PCComparisonExportPath($Format){Assert ($Format -eq 'json') 'JSON format changed';$script:reportTestPath}
    Export-PCSessionComparison 'json'
    Assert ((Get-Content $script:reportTestPath -Raw|ConvertFrom-Json).Kind -eq 'PCInsight.SessionComparison') 'JSON export regressed'
    'PASS: readable comparison content, encoding, blocked and missing values, offline document, safe save/replace, failed-write preservation, shared export handler, immutable dialog snapshot, cancellation and JSON export'
}finally{Remove-Item -LiteralPath $dir -Recurse -Force}
