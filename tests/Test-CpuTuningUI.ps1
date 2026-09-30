$ErrorActionPreference='Stop'
function Assert($ok,$message){if(-not $ok){throw $message}}
$ui=@{};foreach($n in 'CpuReadinessText','CpuControlTable','CpuReadinessScan','CpuBaselineRun','CpuReadinessExport','CpuVendorHelp','Status'){
 $c=[pscustomobject]@{IsEnabled=$false;Text='';ItemsSource=$null;Click=$null};$c|Add-Member ScriptMethod Add_Click {param($handler);$this.Click=$handler};$ui[$n]=$c
}
$script:snapshot=$null;$script:job=$null;$script:updateJob=$null;$script:guide=$null;$script:clockActionBusy=$false;$script:locked=$false;$script:allow=$false;$script:started=$null;$script:saved=$null
function Test-PCClockGuideLocked {$script:locked}
function Confirm($message){$script:allow}
function Get-ActivePlan {'test-plan'}
function Start-Task($kind){$script:started=$kind;$script:job='worker'}
function Show-Error($message){throw $message}
function Save-JsonAtomic($value,$path){$script:saved=$value}
. "$PSScriptRoot/../CpuTuningUI.ps1"
Assert (-not $ui.CpuBaselineRun.IsEnabled -and $ui.CpuReadinessScan.IsEnabled) 'Missing snapshot baseline gate failed'
$script:snapshot=[pscustomobject]@{Timestamp='now';CPU=@([pscustomobject]@{Name='Intel Core i7-13700K';Manufacturer='GenuineIntel'})}
Refresh-PCCpuTuningUI
Assert ($ui.CpuBaselineRun.IsEnabled -and $ui.CpuReadinessExport.IsEnabled) 'Scanned CPU unavailable'
& $ui.CpuBaselineRun.Click;Assert (-not $script:started) 'Cancelled confirmation started worker'
$script:locked=$true;$script:allow=$true;& $ui.CpuBaselineRun.Click;Assert (-not $script:started) 'Guided trial lock bypassed'
$script:locked=$false;$script:updateJob='update';Refresh-PCCpuTuningUI;Assert (-not $ui.CpuReadinessScan.IsEnabled -and -not $ui.CpuBaselineRun.IsEnabled) 'Update lock bypassed'
$script:updateJob=$null;& $ui.CpuBaselineRun.Click
Assert ($script:started -eq 'repeatcpu' -and -not $ui.CpuBaselineRun.IsEnabled -and -not $ui.CpuReadinessScan.IsEnabled) 'Wrong CPU batch dispatch or post-start lock'
function Select-PCCpuReadinessExportPath {$null}
& $ui.CpuReadinessExport.Click;Assert (-not $script:saved) 'Cancelled export saved report'
function Select-PCCpuReadinessExportPath {'mock-report.json'}
& $ui.CpuReadinessExport.Click;Assert ($script:saved.CPUName -eq 'Intel Core i7-13700K' -and -not $script:saved.CanWrite) 'Export lost report identity or invented support'
$script:job=$null;Refresh-PCCpuTuningUI;Assert $ui.CpuBaselineRun.IsEnabled 'Baseline unavailable after idle'
'PASS: actual CPU readiness UI handlers, scan gates, confirmation, guided/update/task locks, batch dispatch and report export'
