# Actual hidden WPF controls and main-window handlers; no hardware or app startup.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
foreach($module in 'Power','Results','SessionExport','SessionDetails','SessionLibrary','SessionComparison','ComparisonReport'){. "$root/$module.ps1"}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Show-SensorHistory {}
function Show-Error($message){$script:lastError=$message}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-library-ui-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory $script:dataDir
try{
    $ui=@{};foreach($element in $xaml.SelectNodes('//*[@Name]')){$ui[$element.Name]=$window.FindName($element.Name)}
    $script:job=$null;$script:updateJob=$null;$script:sessionReadFailed=$false;$script:appVersion='test'
    $script:sessions=@(
        [pscustomobject]@{Timestamp='2026-10-10T10:00:00Z';Test='SHA256-1MiB-parallel-v2';CPUName='CPU A';Completed=$true;MiBPerSecond=100;Frames=@()},
        [pscustomobject]@{Timestamp='2026-10-10T11:00:00Z';Test='OpenGL-test';GPUName='GPU B';Completed=$false;StopReason='Stopped';Frames=@()}
    );$script:history=@()
    . "$root/SessionComparisonUI.ps1"
    . "$root/SessionLibraryUI.ps1"
    $source=Get-Content "$root/PC-Insight.ps1" -Raw -Encoding UTF8
    $start=$source.IndexOf('    function Refresh-SessionPicker {');$end=$source.IndexOf('    function Show-DashboardResult {',$start)
    . ([scriptblock]::Create($source.Substring($start,$end-$start)))
    Refresh-SessionPicker
    Assert ($ui.SessionPicker.Items.Count -eq 2 -and $ui.SessionPicker.SelectedItem.Session.GPUName -eq 'GPU B') 'Initial selection failed'
    $ui.SessionPicker.SelectedIndex=1
    $ui.SessionNote.Text='Factory baseline'
    $ui.SessionPin.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Assert ($script:sessions[0].Pinned -and $script:sessions[0].Note -eq 'Factory baseline' -and $ui.SessionPin.Content -eq 'Unpin result') 'Pin/note click failed'
    $ui.SessionFilter.SelectedItem='CPU'
    Assert ($ui.SessionPicker.Items.Count -eq 1 -and $ui.CompareSessionPicker.Items.Count -eq 1) 'Filtered result hid valid comparison reference'
    $ui.SessionSearch.Text='not found'
    Assert ($ui.SessionPicker.Items.Count -eq 0 -and -not $ui.ExportSessionJson.IsEnabled -and $ui.SessionSensorDetails.Items.Count -eq 0 -and $ui.SessionResults.Text -match 'No session') 'Empty filter left stale details/export'
    $ui.SessionClearFilters.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    $ui.SessionPinnedOnly.IsChecked=$true
    Assert ($ui.SessionPicker.Items.Count -eq 1 -and $ui.SessionNote.Text -eq 'Factory baseline') 'Pinned filter failed'
    $original=$ui.SessionPicker.SelectedItem.Session.Timestamp
    $ui.SessionNote.Text='Draft in progress'
    $script:sessions+= [pscustomobject]@{Timestamp='2026-10-10T12:00:00Z';Test='Sensors-only-v1';Frames=@()}
    Refresh-SessionPicker
    Assert ($ui.SessionPicker.SelectedItem.Session.Timestamp -eq $original) 'New result replaced selection'
    Assert ($ui.SessionNote.Text -eq 'Draft in progress') 'Background refresh discarded unsaved note'
    # Modal save can dispatch events: export a frozen selection even if history changes.
    $script:job='running';$script:updateJob='checking'
    function Select-PCSessionExportPath($Format){$script:sessions[0].Note='Changed during dialog';$ui.SessionPinnedOnly.IsChecked=$false;$ui.SessionPicker.SelectedIndex=0;Join-Path $script:dataDir ('export.'+$Format)}
    Export-SelectedSession 'json'
    $saved=Get-Content (Join-Path $script:dataDir 'export.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($saved.SensorSession.Timestamp -eq $original -and $saved.SensorSession.Note -eq 'Factory baseline') 'Busy export did not freeze selection'
    # Failed persistence never commits annotation changes in memory.
    function Save-PCSessionLibrary {throw 'Simulated disk full'}
    $ui.SessionNote.Text='Should not save';Save-PCSelectedSessionAnnotation $true
    Assert ($script:lastError -eq 'Simulated disk full' -and -not $ui.SessionPicker.SelectedItem.Session.Pinned) 'Write failure changed in-memory pin'
    $script:sessionReadFailed=$true;Refresh-SessionPicker
    Assert (-not $ui.SessionPin.IsEnabled -and $ui.SessionLibraryStatus.Text -match 'preserved') 'Unreadable history did not disable edits'
    if($env:GITHUB_ACTIONS -eq 'true'){
        # Render the actual WPF page at both supported sizes for visual review.
        $script:sessionReadFailed=$false;$script:job=$null;$script:updateJob=$null
        $ui.SessionSearch.Text='';$ui.SessionFilter.SelectedItem='All';$ui.SessionPinnedOnly.IsChecked=$false
        Refresh-SessionPicker
        $ui.Navigation.SelectedIndex=4
        foreach($item in $ui.Navigation.Items){if($item.Header -eq 'Test results'){$ui.Navigation.SelectedItem=$item;break}}
        $ui.InstalledVersion.Text='Installed version: 0.30.0';$ui.Status.Text='Preview with synthetic saved results - no hardware access'
        . "$root/Branding.ps1"
        Set-PCWindowBranding -Window $window -Root $root -Version '0.30.0'
        $script:sessionAnnotationKey='';Show-PCSessionAnnotation
        $output=Join-Path $root 'outputs/release';$null=New-Item -ItemType Directory $output -Force
        foreach($size in @(@(1320,920),@(1000,720))){
            $content=$window.Content
            $content.Measure([Windows.Size]::new($size[0],$size[1]))
            $content.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$content.UpdateLayout()
            Assert ($ui.ResultsPageScroll.ViewportHeight -gt 350 -and $ui.ResultsPageScroll.ScrollableHeight -gt 0) 'Results page lacks usable full-page scrolling' 
            $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$size[0],[int]$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($content)
            $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Create((Join-Path $output ('Results-'+$size[0]+'.png')))
            try{$encoder.Save($stream)}finally{$stream.Dispose()}
        }
    }
    'PASS: WPF result filters, pin/note persistence, all-session comparison references, empty state, selection retention, busy export snapshot and failed-write preservation'
}finally{$window.Close();Remove-Item $script:dataDir -Recurse -Force}
