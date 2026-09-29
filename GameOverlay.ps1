function Initialize-PCOverlayNative {
    if(-not ('PCInsightOverlayNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'OverlayNative.cs')}
}
function Get-PCPresentMonPath {
    $path=Join-Path $PSScriptRoot 'vendor/PresentMon/PresentMon-2.6.0-x64.exe'
    if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af'){
        throw 'FPS component is missing or changed. Reinstall the complete PC Insight update.'
    }
    return $path
}
function Get-PCOverlayTemperatures($Frame,[datetimeoffset]$Now=[datetimeoffset]::Now) {
    $result=[pscustomobject]@{CPU='--';GPU='--';GPULabel='GPU';Issue='Waiting for temperature readings'}
    if(-not $Frame){return $result}
    $timestamp=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Frame.Timestamp,[ref]$timestamp) -or ($Now-$timestamp).TotalSeconds -gt 5 -or $timestamp -gt $Now.AddSeconds(1)){
        $result.Issue='Temperature readings are stale';return $result
    }
    if($null -ne $Frame.CPUCelsius -and $Frame.CPUCelsius -gt 0 -and $Frame.CPUCelsius -lt 125){$result.CPU=('{0:0} C' -f $Frame.CPUCelsius)}
    $gpu=@($Frame.Sensors|Where-Object{$_.Parent -match '^/gpu' -and $_.Type -eq 'Temperature' -and $_.Name -eq 'GPU Core' -and $null -ne $_.Value -and $_.Value -gt 0 -and $_.Value -lt 125})
    if($gpu.Count){$result.GPU=('{0:0} C' -f ($gpu|Measure-Object Value -Maximum).Maximum)}
    if(@($gpu.Parent|Select-Object -Unique).Count -gt 1){$result.GPULabel='GPU max'}
    $result.Issue=[string]$Frame.Issue
    return $result
}
function New-PCOverlayFpsReport($Diagnostics,[string]$TargetName,[string]$Status,[bool]$Administrator,[string]$Version) {
    # A snapshot only; no running Process object or broader process list is exported.
    [pscustomobject]@{
        Schema=1;AppVersion=$Version;CapturedAt=([datetimeoffset]::Now.ToString('o'))
        TargetProcess=$TargetName;AdministratorAccess=$Administrator;Status=$Status
        Capture=$Diagnostics
    }
}
