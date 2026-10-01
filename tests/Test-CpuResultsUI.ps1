$ErrorActionPreference='Stop'
. "$PSScriptRoot/Test-CpuResults.ps1"
$ui=@{}
foreach($name in @('CpuBatchBefore','CpuBatchAfter','CpuBatchBeforeText','CpuBatchAfterText','CpuBatchVerdict','CpuBatchRefresh','CpuBatchExport','Status')){
    $control=[pscustomobject]@{Text='';IsEnabled=$false;ItemsSource=$null;SelectedItem=$null;Click=$null;SelectionChanged=$null}
    $control | Add-Member ScriptMethod Add_Click {param($handler);$this.Click=$handler}
    $control | Add-Member ScriptMethod Add_SelectionChanged {param($handler);$this.SelectionChanged=$handler}
    $ui[$name]=$control
}
function Show-Error($message){throw $message}
function Save-JsonAtomic($value,$path){$script:saved=$value}
$script:history=@();$script:saved=$null
. "$PSScriptRoot/../CpuResultsUI.ps1"
Assert (-not $ui.CpuBatchExport.IsEnabled -and -not $script:cpuBatchComparison) 'Empty UI enabled export'
$script:history=@(New-Runs 'a' 1000)+@(New-Runs 'b' 990 248)
& $ui.CpuBatchRefresh.Click
Assert ($ui.CpuBatchExport.IsEnabled -and $script:cpuBatchComparison.Comparable) 'Saved comparisons not displayed'
$beforeId=$ui.CpuBatchBefore.SelectedItem.BatchId;$afterId=$ui.CpuBatchAfter.SelectedItem.BatchId
$script:history+=@(New-Runs 'c' 980 245)
Refresh-PCCpuResultsUI
Assert ($ui.CpuBatchBefore.SelectedItem.BatchId -eq $beforeId -and $ui.CpuBatchAfter.SelectedItem.BatchId -eq $afterId) 'Refresh silently replaced selections'
function Select-PCCpuBatchExportPath {$null}
& $ui.CpuBatchExport.Click;Assert (-not $script:saved) 'Cancelled export wrote data'
function Select-PCCpuBatchExportPath {$ui.CpuBatchBefore.SelectedItem=$ui.CpuBatchAfter.SelectedItem;Show-PCCpuBatchComparison;'report.json'}
& $ui.CpuBatchExport.Click
Assert ($script:saved.Comparable -and $script:saved.Before.BatchId -eq $beforeId -and -not $script:cpuBatchComparison.Comparable) 'Export did not preserve pre-dialog snapshot'
'PASS: CPU result UI empty state, selection preservation, cancellation and export snapshot during selection changes'
