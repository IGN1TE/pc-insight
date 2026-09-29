# Hidden WPF integration; no app startup, hardware access or saved user data.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$root=Split-Path $PSScriptRoot
. "$root/Results.ps1"
. "$root/SessionExport.ps1"
. "$root/SessionDetails.ps1"
. "$root/SessionComparison.ps1"
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
try{
    $script:ui=@{}
    foreach($name in @('SessionPicker','CompareSessionPicker','ComparisonRows','ComparisonStatus','ComparisonNotes','ExportComparison','ComparisonExportStatus')){$ui[$name]=$window.FindName($name);if(-not $ui[$name]){throw "Missing $name"}}
    $script:job=$null;$script:updateJob=$null
    . "$root/SessionComparisonUI.ps1"
    $a=[pscustomobject]@{Test='SHA256-1MiB-parallel-v2';CPUName='Test CPU';Workers=8;Runtime='4.0';Completed=$true;MiBPerSecond=100;Seconds=20;Frames=@();Timestamp='A'}
    $b=$a|Select-Object *;$b.MiBPerSecond=105;$b.Timestamp='B'
    $items=@([pscustomobject]@{Label='B';Session=$b},[pscustomobject]@{Label='A';Session=$a})
    $ui.SessionPicker.ItemsSource=$items;$ui.CompareSessionPicker.ItemsSource=$items
    $ui.SessionPicker.SelectedIndex=0;$ui.CompareSessionPicker.SelectedIndex=1
    if(-not $ui.ExportComparison.IsEnabled -or $ui.ComparisonRows.Items.Count -ne 2 -or -not $script:sessionComparison.ScoreComparable){throw 'Selection did not display the comparison'}
    $script:job='busy';Show-PCSessionComparison
    if(-not $ui.ExportComparison.IsEnabled){throw 'Read-only comparison export disabled during task'}
    $script:job=$null;$ui.CompareSessionPicker.SelectedIndex=0
    if($ui.ExportComparison.IsEnabled -or $script:sessionComparison -or $ui.ComparisonRows.Items.Count){throw 'Same-session selection kept stale data'}
    $ui.CompareSessionPicker.SelectedIndex=1;$ui.SessionPicker.SelectedIndex=-1;Show-PCSessionComparison
    if($ui.ExportComparison.IsEnabled -or $script:sessionComparison){throw 'Empty selection kept stale export'}
    'PASS: WPF comparison selection, rows, same-session reset, empty state and saved-data export during tasks'
}finally{$window.Close()}
