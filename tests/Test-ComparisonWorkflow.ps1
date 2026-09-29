# Real WPF selectors and click handler with synthetic saved sessions; no hardware or app startup.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
foreach($module in 'Power','Results','SessionExport','SessionDetails','SessionComparison'){. "$root/$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Show-SensorHistory {}
function Show-Error($message){throw $message}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$exportPath=Join-Path ([IO.Path]::GetTempPath()) ('pc-comparison-'+[guid]::NewGuid().ToString('N')+'.json')
try{
    $script:ui=@{}
    foreach($element in $xaml.SelectNodes('//*[@Name]')){$ui[$element.Name]=$window.FindName($element.Name)}
    $script:job=$null;$script:updateJob=$null;$script:jobKind='monitor'
    . "$root/SessionComparisonUI.ps1"
    $script:sessions=@(1..3|ForEach-Object {
        [pscustomobject]@{Timestamp="2026-09-29T12:0$($_):00Z";Test='SHA256-1MiB-parallel-v2';CPUName='Test CPU';Workers=8;Runtime='4.0';Completed=$true;MiBPerSecond=100+$_;Seconds=20;Frames=@()}
    })
    $script:history=@($script:sessions)
    $source=Get-Content "$root/PC-Insight.ps1" -Raw -Encoding UTF8
    $start=$source.IndexOf('    function Refresh-SessionPicker {');$end=$source.IndexOf('    function Export-SelectedSession(',$start)
    . ([scriptblock]::Create($source.Substring($start,$end-$start)))
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    $busyFunction=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-Busy'},$true)
    . ([scriptblock]::Create($busyFunction.Extent.Text))
    Refresh-SessionPicker
    Assert ($ui.ExportComparison.IsEnabled -and $ui.CompareSessionPicker.Items.Count -eq 2) 'Initial reference selection failed'
    $oldReference=$ui.CompareSessionPicker.SelectedItem.Session
    $ui.SessionPicker.SelectedIndex=1
    Assert ($ui.ExportComparison.IsEnabled -and -not (Test-PCSameComparisonSession $ui.CompareSessionPicker.SelectedItem.Session $oldReference)) 'Selecting old reference disabled export instead of choosing a distinct reference'
    $ui.CompareSessionPicker.SelectedIndex=1
    $chosen=$ui.CompareSessionPicker.SelectedItem.Session
    $ui.SessionPicker.SelectedIndex=0
    Assert (Test-PCSameComparisonSession $chosen $ui.CompareSessionPicker.SelectedItem.Session) 'Valid reference was not preserved'
    $script:job='monitoring';Set-Busy $true
    Assert ($ui.ExportComparison.IsEnabled -and $ui.ComparisonStatus.Text -like 'Matching*') 'Monitoring disabled an existing comparison'
    $script:job=$null;$script:updateJob='checking';Set-Busy $true;Show-PCSessionComparison
    Assert $ui.ExportComparison.IsEnabled 'Update check disabled saved-data export'
    $script:updateJob=$null;Set-Busy $false
    # Exercise the actual button event. Only the file picker is stubbed; atomic save is real.
    $script:testComparisonPath=$exportPath
    $originalTime=$script:sessionComparison.Before.Timestamp
    $originalScore=$script:sessionComparison.Rows[0].After
    function Select-PCComparisonExportPath {
        $script:sessionComparison.Before.Timestamp='changed while dialog open'
        $script:sessionComparison.Rows[0].After=999
        $script:testComparisonPath
    }
    $ui.ExportComparison.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $saved=Get-Content $exportPath -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($saved.Before.Timestamp -eq $originalTime -and $saved.Rows[0].After -eq $originalScore) 'Export changed after the save dialog opened'
    function Select-PCComparisonExportPath {return}
    $prior=(Get-FileHash $exportPath).Hash
    $ui.ExportComparison.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ((Get-FileHash $exportPath).Hash -eq $prior) 'Cancel changed exported file'
    $script:sessions=@($script:sessions[0]);Refresh-SessionPicker
    Assert (-not $ui.ExportComparison.IsEnabled -and $ui.ComparisonExportStatus.Text -like 'Save at least two*') 'Single-session state failed to explain unavailable export'
    $script:sessions=@();Refresh-SessionPicker
    Assert (-not $ui.ExportComparison.IsEnabled -and $ui.ComparisonExportStatus.Text -like 'Choose a saved session*') 'Empty state retained stale export'
    'PASS: full selector workflow, reference preservation, monitoring/update export, actual button save, immutable dialog snapshot, cancellation and empty states'
}finally{
    $window.Close()
    if(Test-Path -LiteralPath $exportPath){Remove-Item -LiteralPath $exportPath -Force}
    if(Test-Path -LiteralPath ($exportPath+'.tmp')){Remove-Item -LiteralPath ($exportPath+'.tmp') -Force}
}
