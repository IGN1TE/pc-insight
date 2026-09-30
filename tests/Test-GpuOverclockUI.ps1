# Windows-only WPF interaction test. All GPU access is mocked; no driver settings change.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root/GpuOverclock.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Add-Type -AssemblyName PresentationFramework
[xml]$xaml=Get-Content "$root/MainWindow.xaml" -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-clock-ui-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $dataDir
$script:ui=@{}
foreach($name in 'DetectClocks','ClockGPU','ClockInfo','CoreOffset','MemoryOffset','ApplyClocks','RestoreClocks','ClockStatus'){$ui[$name]=$window.FindName($name);Assert ($null -ne $ui[$name]) "Missing $name"}
$script:job=$null;$script:updateJob=$null;$script:guide=$null;$script:isAdministrator=$true
$script:allowClockChange=$false;$script:clockWriteCount=0;$script:clockUiError=''
$script:clockLive=[pscustomobject]@{UUID='GPU-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';Name='Mock GPU';Label='Mock GPU';Driver='mock';Available=$true;CoreMHz=0;MemoryMHz=0;CoreMin=-500;CoreMax=500;MemoryMin=-1000;MemoryMax=2000;TemperatureC=50}
function Get-PCClockDevices {$script:clockLive|Select-Object *}
function Get-PCClockDevice($UUID){Assert ($UUID -eq $script:clockLive.UUID) 'Wrong GPU';$script:clockLive|Select-Object *}
function Test-PCClockAdministrator {$script:isAdministrator}
function Set-PCClockOffset($UUID,$Domain,$MHz){Assert (Test-Path $script:clockJournalPath) 'Write before journal';$script:clockWriteCount++;if($Domain -eq 0){$script:clockLive.CoreMHz=$MHz}else{$script:clockLive.MemoryMHz=$MHz}}
function Set-Busy($Busy){Update-PCClockControlState $Busy}
function Confirm($message){$script:clockReview=$message;$script:allowClockChange}
function Show-Error($message){$script:clockUiError=$message}
function Click($Name){$ui[$Name].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
try{
    . "$root/GpuOverclockUI.ps1"
    Assert (-not $ui.ApplyClocks.IsEnabled -and -not $ui.RestoreClocks.IsEnabled -and $script:clockWriteCount -eq 0) 'Startup wrote or enabled undetected clocks'
    Click 'DetectClocks'
    Assert ($ui.ApplyClocks.IsEnabled -and $ui.CoreOffset.Text -eq '0' -and $script:clockWriteCount -eq 0) 'Detection failed or wrote clocks'
    $ui.CoreOffset.Text='50';$ui.MemoryOffset.Text='100'
    Click 'ApplyClocks'
    Assert ($script:clockWriteCount -eq 0 -and -not (Test-Path $script:clockJournalPath)) 'Cancelled review changed settings'
    Assert ($script:clockReview.Contains($script:clockLive.UUID) -and $script:clockReview.Contains('50 MHz')) 'Review omitted target GPU/offset'
    $script:allowClockChange=$true
    Click 'ApplyClocks'
    Assert ($script:clockWriteCount -eq 2 -and $script:clockLive.CoreMHz -eq 50 -and $script:clockLive.MemoryMHz -eq 100 -and $ui.RestoreClocks.IsEnabled -and -not $script:clockUiError) 'Apply click did not journal/write/readback'
    $script:job='benchmark';Update-PCClockControlState
    Assert (-not $ui.ApplyClocks.IsEnabled -and -not $ui.RestoreClocks.IsEnabled) 'Clock changes enabled during benchmark'
    $count=$script:clockWriteCount;Click 'ApplyClocks';Assert ($script:clockWriteCount -eq $count) 'Busy handler wrote clocks'
    $script:job=$null;$script:guide=[pscustomobject]@{Phase='Decision'};Update-PCClockControlState
    Assert (-not $ui.ApplyClocks.IsEnabled) 'Guided decision allowed manual clocks'
    $script:guide=$null;$script:isAdministrator=$false;Update-PCClockControlState
    Assert (-not $ui.ApplyClocks.IsEnabled -and -not $ui.RestoreClocks.IsEnabled) 'Non-admin write controls enabled'
    $script:isAdministrator=$true;Update-PCClockControlState
    $script:allowClockChange=$false;Click 'RestoreClocks'
    Assert ($script:clockLive.CoreMHz -eq 50 -and (Test-Path $script:clockJournalPath)) 'Cancelled restore changed settings'
    $script:allowClockChange=$true;Click 'RestoreClocks'
    Assert ($script:clockLive.CoreMHz -eq 0 -and $script:clockLive.MemoryMHz -eq 0 -and -not (Test-Path $script:clockJournalPath)) 'Restore click failed'
    $script:clockLive.Available=$false;$script:clockLive|Add-Member NoteProperty Issue 'Unsupported mock device'
    Click 'DetectClocks'
    Assert (-not $ui.ApplyClocks.IsEnabled -and $ui.ClockInfo.Text -eq 'Unsupported mock device') 'Unsupported device enabled write'
    'PASS: actual WPF detection/review/cancel/apply/restore handlers, busy/guide/admin gates, unsupported state and no startup writes (mock GPU only)'
}finally{$window.Close();Remove-Item $dataDir -Recurse -Force}
