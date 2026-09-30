$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Updates.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject($action,$message){$blocked=$false;try{& $action|Out-Null}catch{$blocked=$true};Assert $blocked $message}
$m=[pscustomobject]@{appId='PCInsight.PerUser';schema=1;version='0.16.0';downloadUrl='https://example.com/release.zip';sha256=('a'*64);sizeBytes=123}
Assert ((Read-PCUpdateManifest $m '0.15.0').Available) 'New release must be detected'
Assert (-not (Read-PCUpdateManifest $m '0.16.0').Available) 'Same version must not update'
Assert (-not (Read-PCUpdateManifest $m '0.17.0').Available) 'Downgrade must not update'
Reject {Assert-PCUpdateUrl 'http://example.com/feed'} 'HTTP accepted'
Reject {Assert-PCUpdateUrl 'https://user:password@example.com/feed'} 'Credentials accepted'
$m.sha256='bad';Reject {Read-PCUpdateManifest $m '0.15.0'} 'Invalid checksum accepted'
$m.sha256='a'*64;$m.sizeBytes=999999999;Reject {Read-PCUpdateManifest $m '0.15.0'} 'Oversize release accepted'
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pc-updates-'+[guid]::NewGuid())
$null=New-Item -ItemType Directory $folder
Add-Type -AssemblyName System.IO.Compression.FileSystem
try{
 foreach($name in @('PC-Insight/../../escape.ps1','PC-Insight/..\..\escape.ps1','other/PC-Insight.ps1','PC-Insight/file.ps1:stream')){
  $archive=Join-Path $folder ([guid]::NewGuid().ToString()+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($archive,'Create');$null=$zip.CreateEntry($name);$zip.Dispose()
  Reject {Expand-PCUpdate $archive (Join-Path $folder ([guid]::NewGuid().ToString()))} 'Unsafe path accepted'
 }
 $archive=Join-Path $folder 'good.zip';$zip=[IO.Compression.ZipFile]::Open($archive,'Create')
 foreach($name in @('PC-Insight.ps1','Install.ps1','MainWindow.xaml','version.json','vendor/LibreHardwareMonitor/hashes.json')){
  $entry=$zip.CreateEntry('PC-Insight/'+$name);$writer=[IO.StreamWriter]::new($entry.Open());$writer.Write('fixture');$writer.Dispose()
 }
 $zip.Dispose()
 $source=Expand-PCUpdate $archive (Join-Path $folder 'expanded')
 Assert (Test-Path (Join-Path $source 'PC-Insight.ps1')) 'Valid package did not extract'
 'PASS: versions, transport URLs, checksum metadata, size bounds, unsafe paths, valid package extraction'
}finally{Remove-Item $folder -Recurse -Force}
# Stub only the network boundary; exercise the actual response/redirect loop.
function New-PCUpdateRequest([string]$Url) {
    $script:requested += $Url
    $request=[pscustomobject]@{}
    $request|Add-Member ScriptMethod GetResponse {
        if($script:requested.Count -gt 6){throw 'Unexpected recursive request'}
        $response=$script:responses.Dequeue()
        return $response
    }
    return $request
}
function FakeResponse($status,$location) {
    $response=[pscustomobject]@{StatusCode=$status;Headers=@{Location=$location};Disposed=$false}
    $response|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    return $response
}
$script:requested=@();$script:responses=[Collections.Queue]::new()
$redirect=FakeResponse 302 'https://assets.example.com/release.zip'
$ok=FakeResponse 200 ''
$script:responses.Enqueue($redirect);$script:responses.Enqueue($ok)
$result=Open-PCUpdateResponse 'https://example.com/release.zip'
Assert ($result.StatusCode -eq 200 -and $script:requested.Count -eq 2 -and $redirect.Disposed) 'HTTPS redirect request loop failed'
$script:requested=@();$script:responses=[Collections.Queue]::new()
$script:responses.Enqueue((FakeResponse 302 'http://example.com/insecure'))
Reject {Open-PCUpdateResponse 'https://example.com/release.zip'} 'HTTPS downgrade accepted'
$script:requested=@();$script:responses=[Collections.Queue]::new()
1..6|ForEach-Object{$script:responses.Enqueue((FakeResponse 302 '/loop'))}
Reject {Open-PCUpdateResponse 'https://example.com/loop'} 'Redirect limit not enforced'
Assert ($script:requested.Count -eq 6) 'Wrong redirect limit'
'PASS: network helper uses request response, follows HTTPS redirects, blocks downgrade and redirect loops'
# Version source and optional release notes must stay backward compatible.
Assert ((Get-PCAppVersion (Join-Path $PSScriptRoot '..')) -eq '0.28.0') 'Runtime version did not come from metadata'
$manifest=[pscustomobject]@{appId='PCInsight.PerUser';schema=1;version='0.17.0';downloadUrl='https://example.com/app.zip';sha256=('a'*64);sizeBytes=123;releaseNotes='New release'}
Assert ((Read-PCUpdateManifest $manifest '0.16.0').ReleaseNotes -eq 'New release') 'Notes were not returned'
$manifest.releaseNotes='x'*13000
Assert ((Read-PCUpdateManifest $manifest '0.16.0').ReleaseNotes.Length -lt 12100) 'Notes were not bounded'
$manifest.PSObject.Properties.Remove('releaseNotes')
Assert ((Read-PCUpdateManifest $manifest '0.16.0').ReleaseNotes -eq '') 'Legacy feed without notes rejected'
'PASS: shared version metadata and optional bounded release notes'
