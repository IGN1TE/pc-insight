# Windows-only read-only WPF load test. No app startup or hardware access.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$root=Split-Path $PSScriptRoot
[xml]$xaml=Get-Content (Join-Path $root 'MainWindow.xaml') -Raw -Encoding UTF8
$reader=[Xml.XmlNodeReader]::new($xaml)
$window=[Windows.Markup.XamlReader]::Load($reader)
try {
 $source=Get-Content (Join-Path $root 'PC-Insight.ps1') -Raw -Encoding UTF8
 $bindingLine=(@($source -split '\r?\n' | Where-Object {$_ -match 'ForEach-Object.*FindName'}) -join "`n")
 foreach($match in [regex]::Matches($bindingLine,"'([^']+)'")){
  if(-not $window.FindName($match.Groups[1].Value)){throw ('Missing control: '+$match.Groups[1].Value)}
 }
 . (Join-Path $root 'Updates.ps1')
 $nav=$window.FindName('Navigation')
 $nav.Tag='AFTERBURN / PREVIEW '+(Get-PCAppVersion $root)
 $null=$nav.ApplyTemplate()
 $footer=$nav.Template.FindName('SidebarVersion',$nav)
 $footer.GetBindingExpression([Windows.Controls.TextBlock]::TextProperty).UpdateTarget()
 if($footer.Text -ne $nav.Tag){throw 'Sidebar did not display the installed version'}
 [xml]$overlayXaml=Get-Content (Join-Path $root 'GameOverlay.xaml') -Raw -Encoding UTF8
 $overlay=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($overlayXaml))
 try{
  foreach($name in 'OverlayCpu','OverlayGpu','OverlayGpuLabel','OverlayFps','OverlayTarget','OverlayHint'){
   if(-not $overlay.FindName($name)){throw ('Missing overlay control: '+$name)}
  }
  if($overlay.ShowActivated -or $overlay.ShowInTaskbar -or -not $overlay.AllowsTransparency){throw 'Overlay passive-window settings changed'}
  . (Join-Path $root 'GameOverlay.ps1')
  Initialize-PCOverlayNative
  $script:windowHotkeyPresses=0
  $adapter=[PCInsightOverlayHotkey]::new(0x5043,[Action]{$script:windowHotkeyPresses++})
  $hook=[Delegate]::CreateDelegate([Windows.Interop.HwndSourceHook],$adapter,'HandleMessage')
  $handled=$false
  $null=$hook.Invoke([IntPtr]::Zero,0x0312,[IntPtr]0x5043,[IntPtr]::Zero,[ref]$handled)
  if(-not $handled -or $script:windowHotkeyPresses -ne 1){throw 'Actual WPF hotkey delegate did not dispatch and mark the message handled'}
  # Create the hidden overlay HWND and verify native click-through/no-activation style read-back.
  [PCInsightOverlayNative]::MakePassive([Windows.Interop.WindowInteropHelper]::new($overlay).EnsureHandle())
 }finally{$overlay.Close()}
 'PASS: WPF XAML loads and named controls bind. Visual scaling still needs manual inspection.'
}finally{$window.Close()}
