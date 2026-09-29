# Normal shortcuts launch this script with -WindowStyle Hidden.
# Catch early load/parse failures as well as the main app's own error dialogs.
#requires -Version 5.1
param([switch]$WaitForPreviousInstance)
$ErrorActionPreference='Stop'
try{
    & (Join-Path $PSScriptRoot 'PC-Insight.ps1') -WaitForPreviousInstance:$WaitForPreviousInstance
    if(-not $?){exit 1}
}catch{
    $details=$_.Exception.ToString()
    $logPath=Join-Path $env:LOCALAPPDATA 'PCInsight/startup-error.log'
    $message='PC Insight could not start. '+$_.Exception.Message
    try{
        $null=New-Item -ItemType Directory -Path (Split-Path $logPath) -Force
        Set-Content -LiteralPath $logPath -Value ((Get-Date).ToString('o')+[Environment]::NewLine+$details) -Encoding UTF8
        $message+=[Environment]::NewLine+[Environment]::NewLine+'Details: '+$logPath
    }catch{}
    try{
        Add-Type -AssemblyName PresentationFramework
        $null=[Windows.MessageBox]::Show($message,'PC Insight startup error','OK','Error')
    }catch{Write-Host $message}
    exit 1
}
