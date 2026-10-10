# Read-only support probe. Never calls an offset setter or changes GPU settings.
# Run in Windows PowerShell: .\tools\Read-GpuClockSupport.ps1 -OutputPath .\gpu-clock-support.json
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
. "$root/GpuOverclock.ps1"
. "$root/Updates.ps1"
$devices=@();$issue=$null;$admin=$false
try{$admin=Test-PCClockAdministrator;$devices=@(Get-PCClockDevices)}catch{$issue=$_.Exception.Message}
$report=[pscustomobject]@{Schema=1;Kind='PCInsight.ClockSupport';AppVersion=(Get-PCAppVersion $root);CapturedAt=([datetimeoffset]::Now.ToString('o'));Administrator=$admin;Process64Bit=[Environment]::Is64BitProcess;Devices=$devices;Issue=$issue}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output ('Saved read-only GPU clock support report: '+[IO.Path]::GetFullPath($OutputPath))
