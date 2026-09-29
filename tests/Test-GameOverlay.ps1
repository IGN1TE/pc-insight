$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GameOverlay.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
Initialize-PCOverlayNative
# Reproduce the HwndSourceHook signature without requiring WPF on Linux.
# The actual WPF delegate is also exercised in Test-Interface on Windows.
if(-not ('PCInsightTestWindowHook' -as [type])){
    Add-Type 'public delegate System.IntPtr PCInsightTestWindowHook(System.IntPtr window, int message, System.IntPtr wparam, System.IntPtr lparam, ref bool handled);'
}
$script:hotkeyPresses=0
$adapter=[PCInsightOverlayHotkey]::new(0x5043,[Action]{$script:hotkeyPresses++})
$hook=[Delegate]::CreateDelegate([PCInsightTestWindowHook],$adapter,'HandleMessage')
$handled=$false
$null=$hook.Invoke([IntPtr]::Zero,0x0312,[IntPtr]0x5044,[IntPtr]::Zero,[ref]$handled)
Assert (-not $handled -and $script:hotkeyPresses -eq 0) 'Another hotkey was intercepted'
$null=$hook.Invoke([IntPtr]::Zero,0x0111,[IntPtr]0x5043,[IntPtr]::Zero,[ref]$handled)
Assert (-not $handled -and $script:hotkeyPresses -eq 0) 'An unrelated window message toggled the overlay'
1..2|ForEach-Object{
    $handled=$false
    $null=$hook.Invoke([IntPtr]::Zero,0x0312,[IntPtr]0x5043,[IntPtr]::Zero,[ref]$handled)
    Assert $handled 'The hotkey was not marked handled through the by-reference delegate'
}
Assert ($script:hotkeyPresses -eq 2) 'Repeated hotkeys did not dispatch exactly once per message'
'PASS: hotkey delegate preserves ref Boolean, filters messages and invokes repeated callbacks without Value-property errors'
$header='Application,ProcessID,SwapChainAddress,TimeInSeconds,msBetweenPresents'
$window=[PCInsightFpsWindow]::new(42)
$window.AddLine($header,0)
for($i=0;$i -le 120;$i++){
    $seconds=($i/60.0).ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture)
    $window.AddLine(('"Game, Test.exe",42,0x1,'+$seconds+',16.666667'),(1000+$i*16))
}
for($i=0;$i -le 240;$i++){
    $seconds=($i/120.0).ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture)
    $window.AddLine(('Other.exe,99,0xforeign,'+$seconds+',8.333333'),(1000+$i*8))
}
1..20|ForEach-Object{$window.AddLine('Game.exe,42,0x1,2.000000,16.666667',2999)}
$reading=$window.Read(3000)
Assert ($null -ne $reading.Fps -and [math]::Abs($reading.Fps-60) -lt 0.01) 'CSV presentation timestamps did not yield 60 FPS'
# A second, slower swap chain must not be added to the foreground app rate.
for($i=0;$i -le 30;$i++){
    $seconds=($i/15.0).ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture)
    $window.AddLine(('Game.exe,42,0x2,'+$seconds+',66.666667'),(1000+$i*64))
}
Assert ([math]::Abs($window.Read(3000).Fps-60) -lt 0.01) 'Swap chains were combined into an inflated FPS'
$diagnostic=$window.GetDiagnostics()
Assert ($diagnostic.AcceptedFrames -eq 152 -and $diagnostic.OtherProcessRows -eq 241 -and $diagnostic.RejectedRows -eq 20) 'Capture details do not distinguish accepted, wrong-process and duplicate rows'
Assert ($diagnostic.HeaderSeen -and $diagnostic.ColumnsSupported) 'Valid CSV header was not reported'
Assert ($null -eq $window.Read(6000).Fps) 'Stale FPS remained visible'
$empty=[PCInsightFpsWindow]::new(42);$empty.AddLine($header,0)
foreach($line in @('game,99,0x1,1,16','game,42,0x1,NaN,16','game,42,0x1,Infinity,16','"bad,42,0x1,1,16','partial')){$empty.AddLine($line,100)}
Assert ($null -eq $empty.Read(100).Fps) 'Malformed or wrong-process frames invented an FPS'
$empty.AddLine('Application,ProcessID,SwapChainAddress,CPUStartTime',0)
$empty.AddLine('game,42,0x1,1000',10)
Assert ($null -eq $empty.Read(100).Fps) 'Unsupported CSV units were treated as seconds'
Assert ($empty.Read(100).Status -match 'format is not supported') 'Unsupported output was hidden behind waiting status'
$silent=[PCInsightFpsWindow]::new(42)
Assert ($silent.Read(10000).Status -match 'No frame data received') 'No-output capture waited indefinitely without explanation'
# Full legacy CSV layout produced by PresentMon with normal GPU/display tracking.
$full=[PCInsightFpsWindow]::new(42)
$full.AddLine('Application,ProcessID,SwapChainAddress,Runtime,SyncInterval,PresentFlags,Dropped,TimeInSeconds,msInPresentAPI,msBetweenPresents,AllowsTearing,PresentMode,msUntilRenderComplete,msUntilDisplayed,msBetweenDisplayChange,msFlipDelay,msUntilRenderStart,msGPUActive',0)
for($i=0;$i -le 120;$i++){
    $seconds=(12+$i/60.0).ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture)
    $full.AddLine(('Game.exe,42,0x1,DXGI,0,512,0,'+$seconds+',0.02,16.666667,1,Composed: Flip,5,8,16.666667,0,0.1,4'),(1000+$i*16))
}
Assert ([math]::Abs($full.Read(3000).Fps-60) -lt 0.01) 'Full PresentMon v1 schema did not produce correct FPS'
$arguments=[PCInsightFpsCapture]::CaptureArguments(42,('PCInsightOverlay-123-'+('a'*32)))
Assert ($arguments -match '--process_id 42 ' -and $arguments -match '--v1_metrics' -and $arguments -notmatch '--no_track_display|--no_track_gpu') 'Standard GPU/display tracking was disabled again'
$snapshot=$full.GetDiagnostics()
$report=New-PCOverlayFpsReport $snapshot 'Game.exe' $full.Read(3000).Status $true '0.21.2'
$full.AddLine('Game.exe,42,0x1,DXGI,0,512,0,15,0.02,16,1,Composed: Flip,5,8,16,0,0.1,4',4000)
$roundtrip=$report|ConvertTo-Json -Depth 8|ConvertFrom-Json
Assert ($roundtrip.TargetProcess -eq 'Game.exe' -and $roundtrip.AdministratorAccess -and $roundtrip.Capture.AcceptedFrames -eq 121) 'Export snapshot mutated or lost target/permissions/capture details'
'PASS: standard capture command, full CSV layout, bounded diagnostics, missing/unsupported output status and immutable report snapshot'
$now=[datetimeoffset]::Parse('2026-09-29T12:00:00Z')
$frame=[pscustomobject]@{Timestamp=$now.ToString('o');CPUCelsius=65;Issue=$null;Sensors=@(
    [pscustomobject]@{Parent='/gpu-nvidia/0';Name='GPU Core';Type='Temperature';Value=62},
    [pscustomobject]@{Parent='/gpu-amd/0';Name='GPU Core';Type='Temperature';Value=50},
    [pscustomobject]@{Parent='/gpu-nvidia/0';Name='GPU Hot Spot';Type='Temperature';Value=78}
)}
$temperatures=Get-PCOverlayTemperatures $frame $now
Assert ($temperatures.CPU -eq '65 C' -and $temperatures.GPU -eq '62 C' -and $temperatures.GPULabel -eq 'GPU max') 'Temperature identity or multi-GPU label is wrong'
$temperatures=Get-PCOverlayTemperatures $frame $now.AddSeconds(6)
Assert ($temperatures.CPU -eq '--' -and $temperatures.GPU -eq '--') 'Stale temperatures remained visible'
$frame.CPUCelsius=$null;$frame.Sensors=@()
$temperatures=Get-PCOverlayTemperatures $frame $now
Assert ($temperatures.CPU -eq '--' -and $temperatures.GPU -eq '--') 'Missing temperatures were treated as zero'
Assert ((Get-PCPresentMonPath) -match 'PresentMon-2.6.0-x64.exe$') 'Bundled FPS executable hash failed'
'PASS: native helper compiles, foreground process isolation, CSV parsing/units, rolling FPS, independent swap chains, stale/missing readings, temperature identity, pinned dependency'
