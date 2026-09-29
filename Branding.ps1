# Load branding from the app folder, independent of the launcher's working directory.
function Set-PCWindowBranding {
    param($Window, [string]$Root = $PSScriptRoot, [string]$Version)
    $logoPath = Join-Path $Root 'assets\branding\pc-insight-logo-v1.png'
    $logo = [Windows.Media.Imaging.BitmapImage]::new()
    $logo.BeginInit()
    $logo.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $logo.UriSource = [uri]([IO.Path]::GetFullPath($logoPath))
    $logo.EndInit()
    $logo.Freeze()
    $Window.Resources['PCInsightLogo'] = $logo

    $iconPath = Join-Path $Root 'PCInsight.ico'
    $iconStream = [IO.File]::OpenRead($iconPath)
    try {
        $Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create(
            $iconStream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        $Window.Icon.Freeze()
    } finally { $iconStream.Dispose() }
    $Window.FindName('Navigation').Tag = 'PREVIEW ' + $Version
    $Window.FindName('AboutVersion').Text = 'Windows desktop preview ' + $Version
}
