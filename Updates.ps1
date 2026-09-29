# Version metadata is shared by UI, reports, and updater comparisons.
function Get-PCAppVersion([string]$AppDirectory=$PSScriptRoot) {
    $metadata=Get-Content -LiteralPath (Join-Path $AppDirectory 'version.json') -Raw|ConvertFrom-Json
    $version=$null
    if($metadata.AppId -ne 'PCInsight.PerUser' -or -not [version]::TryParse([string]$metadata.Version,[ref]$version)){throw 'Application version metadata is invalid.'}
    return $version.ToString()
}
# Updates use an explicitly configured HTTPS release feed; no discovery or telemetry.
function Assert-PCUpdateUrl([string]$Value) {
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'Use a complete HTTPS URL without credentials or a fragment.' }
    return $uri.AbsoluteUri
}
function Read-PCUpdateManifest($Manifest, [string]$CurrentVersion) {
    if ($Manifest.appId -ne 'PCInsight.PerUser' -or $Manifest.schema -ne 1) { throw 'This feed is not a supported PC Insight release feed.' }
    $version = $null
    if (-not [version]::TryParse([string]$Manifest.version,[ref]$version)) { throw 'The release version is invalid.' }
    $url = Assert-PCUpdateUrl ([string]$Manifest.downloadUrl)
    if ([string]$Manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The release checksum is invalid.' }
    $size = 0L
    if (-not [long]::TryParse([string]$Manifest.sizeBytes,[ref]$size) -or $size -lt 1 -or $size -gt 52428800) { throw 'The release size is invalid or exceeds 50 MiB.' }
    $notes=[string]$Manifest.releaseNotes
    if($notes.Length -gt 12000){$notes=$notes.Substring(0,12000)+' (truncated)'}
    [pscustomobject]@{ ReleaseNotes=$notes; Version=$version.ToString(); Available=($version -gt [version]$CurrentVersion); DownloadUrl=$url; SHA256=([string]$Manifest.sha256).ToUpperInvariant(); SizeBytes=$size }
}
function New-PCUpdateRequest([string]$Url) {
    $request=[Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect=$false; $request.Timeout=30000; $request.ReadWriteTimeout=30000
    $request.UserAgent='PCInsight-Updater/'+(Get-PCAppVersion)
    return $request
}
function Open-PCUpdateResponse([string]$Url) {
    $url=Assert-PCUpdateUrl $Url
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    for($hop=0;$hop -lt 6;$hop++){
        $request=New-PCUpdateRequest $url
        $response=$request.GetResponse()
        if([int]$response.StatusCode -eq 200){return $response}
        if([int]$response.StatusCode -notin @(301,302,303,307,308)){$response.Dispose();throw 'Unexpected update server response.'}
        try{$next=[uri]::new([uri]$url,[string]$response.Headers['Location']);$url=Assert-PCUpdateUrl $next.AbsoluteUri}
        finally{$response.Dispose()}
    }
    throw 'Too many update redirects.'
}
function Get-PCUpdate([string]$FeedUrl,[string]$CurrentVersion) {
    $response=Open-PCUpdateResponse $FeedUrl
    $stream=$null; $memory=[IO.MemoryStream]::new()
    try {
        if($response.ContentLength -gt 65536){throw 'Release manifest exceeds 64 KiB.'}
        $stream=$response.GetResponseStream();$buffer=New-Object byte[] 4096
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
            if($memory.Length+$count -gt 65536){throw 'Release manifest exceeds 64 KiB.'}
            $memory.Write($buffer,0,$count)
        }
        $text=[Text.Encoding]::UTF8.GetString($memory.ToArray()).TrimStart([char]0xFEFF)
        Read-PCUpdateManifest ($text|ConvertFrom-Json) $CurrentVersion
    }finally{if($stream){$stream.Dispose()};$memory.Dispose();$response.Dispose()}
}
function Expand-PCUpdate([string]$Archive,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $seen = @{}; $total = 0L
        if ($zip.Entries.Count -gt 3000) { throw 'Too many release files.' }
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if ($name -notmatch '^PC-Insight/' -or $name -match '(^|/)\.\.(/|$)|:|^/' ) { throw 'Unsafe archive path.' }
            $path = [IO.Path]::GetFullPath((Join-Path $Destination $name))
            if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $seen.ContainsKey($path)) { throw 'Unsafe or duplicate archive path.' }
            $seen[$path]=$true; $total += $entry.Length
            if ($total -gt 157286400) { throw 'Expanded release exceeds 150 MiB.' }
        }
        $null=New-Item -ItemType Directory -Path $Destination -Force
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName.Replace('\','/'); $path=Join-Path $Destination $name
            if ($name.EndsWith('/')) { $null=New-Item -ItemType Directory -Path $path -Force; continue }
            $null=New-Item -ItemType Directory -Path (Split-Path $path) -Force
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$path,$false)
        }
        $source=Join-Path $Destination 'PC-Insight'
        foreach($file in 'PC-Insight.ps1','Install.ps1','MainWindow.xaml','version.json','vendor/LibreHardwareMonitor/hashes.json') {
            if(-not(Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)){throw 'Release package is incomplete.'}
        }
        return $source
    } finally { $zip.Dispose() }
}
function Save-PCUpdate($Release,[string]$CacheDirectory) {
    $releaseInfo=Read-PCUpdateManifest ([pscustomobject]@{appId='PCInsight.PerUser';schema=1;version=$Release.Version;downloadUrl=$Release.DownloadUrl;sha256=$Release.SHA256;sizeBytes=$Release.SizeBytes}) '0.0'
    $folder=Join-Path $CacheDirectory ([guid]::NewGuid().ToString())
    $null=New-Item -ItemType Directory -Path $folder -Force
    $archive=Join-Path $folder 'release.zip'
    $response=$null; $inputStream=$null; $outputStream=$null
    try {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $response=Open-PCUpdateResponse $releaseInfo.DownloadUrl
        if ([int]$response.StatusCode -ne 200) { throw 'The release server did not return a direct download.' }
        if ($response.ContentLength -gt $releaseInfo.SizeBytes) { throw 'Release size does not match its manifest.' }
        $inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($archive)
        $buffer=New-Object byte[] 65536; $total=0L
        while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if($total -gt $releaseInfo.SizeBytes){throw 'Download exceeds the declared release size.'}
            $outputStream.Write($buffer,0,$count)
        }
        $outputStream.Dispose();$outputStream=$null
        if($total -ne $releaseInfo.SizeBytes -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne $releaseInfo.SHA256){throw 'Release verification failed. Nothing was installed.'}
        $source=Expand-PCUpdate $archive (Join-Path $folder 'expanded')
        $metadata=Get-Content (Join-Path $source 'version.json') -Raw|ConvertFrom-Json
        if($metadata.AppId -ne 'PCInsight.PerUser' -or [version]$metadata.Version -ne [version]$releaseInfo.Version){throw 'Package version does not match the release feed.'}
        return $source
    } finally {
        if($outputStream){$outputStream.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()}
    }
}
