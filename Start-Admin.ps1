# Launch an elevated instance only after the user chooses the Admin launcher.
$ErrorActionPreference = 'Stop'
try {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $main = Join-Path $PSScriptRoot 'Start-App.ps1'
    Start-Process -FilePath $exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $main)
} catch {
    $message='Administrator launch was cancelled or failed. '+$_.Exception.Message
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show($message,'PC Insight','OK','Information')|Out-Null
}
