$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Results.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
function Show-Error($message){throw $message}
function Save-JsonAtomic($value,$path){$script:saved=$value}
$ui=@{}
foreach($name in 'EnduranceHistory','EnduranceHistoryDetails','EnduranceHistoryRefresh','EnduranceHistoryExport','Status'){
    $c=[pscustomobject]@{Text='';IsEnabled=$false;ItemsSource=$null;SelectedItem=$null;Click=$null;SelectionChanged=$null}
    $c|Add-Member ScriptMethod Add_Click {param($handler);$this.Click=$handler}
    $c|Add-Member ScriptMethod Add_SelectionChanged {param($handler);$this.SelectionChanged=$handler}
    $ui[$name]=$c
}
$script:sessions=@();$script:saved=$null
. "$PSScriptRoot/../EnduranceResultsUI.ps1"
Assert (-not $ui.EnduranceHistoryExport.IsEnabled -and $ui.EnduranceHistoryDetails.Text -match 'No saved') 'Empty state incorrect'
$a=[pscustomobject]@{Test='GPU-endurance-300s-v1';Timestamp='2026-10-10T10:00:00Z';RequestedSeconds=300;Seconds=300;Completed=$true;EnduranceOutcome='Completed';Frames=@();ReliabilityEvidence=$null}
$b=[pscustomobject]@{Test='GPU-endurance-600s-v1';Timestamp='2026-10-10T11:00:00Z';RequestedSeconds=600;Seconds=20;Completed=$false;StopReason='Cancelled';EnduranceOutcome='Stopped: Cancelled';Frames=@();ReliabilityEvidence=[pscustomobject]@{Status='Events found';Checks=@();Events=@([pscustomobject]@{Provider='Display';Id=4101});Limitations='Fixture'}}
$script:sessions=@($a,$b,[pscustomobject]@{Test='RAM-copy';Timestamp='2026-10-10T12:00:00Z'})
& $ui.EnduranceHistoryRefresh.Click
Assert ($ui.EnduranceHistory.ItemsSource.Count -eq 2 -and $ui.EnduranceHistory.SelectedItem.Session -eq $b -and $ui.EnduranceHistory.SelectedItem.Label -match 'events to review') 'Latest endurance/filter/status failed'
$ui.EnduranceHistory.SelectedItem=$ui.EnduranceHistory.ItemsSource[1];& $ui.EnduranceHistory.SelectionChanged
Assert ($ui.EnduranceHistoryDetails.Text -match 'not collected') 'Legacy session evidence invented'
Refresh-PCEnduranceResults
Assert ($ui.EnduranceHistory.SelectedItem.Session -eq $a) 'Refresh replaced selection'
function Select-PCEnduranceExportPath {$null}
& $ui.EnduranceHistoryExport.Click;Assert (-not $script:saved) 'Cancelled export wrote data'
function Select-PCEnduranceExportPath {$ui.EnduranceHistory.SelectedItem=$ui.EnduranceHistory.ItemsSource[0];'session.json'}
& $ui.EnduranceHistoryExport.Click
Assert ($script:saved.Seconds -eq 300 -and $script:saved.Test -eq $a.Test) 'Export did not freeze selection before dialog'
$script:sessions=@();Refresh-PCEnduranceResults
Assert (-not $ui.EnduranceHistoryExport.IsEnabled) 'Expired selection left export enabled'
'PASS: endurance history empty/legacy/partial/event states, selection preservation, expiry and export snapshots'
