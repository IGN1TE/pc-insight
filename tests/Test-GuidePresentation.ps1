$ErrorActionPreference='Stop'
. "$PSScriptRoot/../GuidePresentation.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
# Synthetic values reproduce the overlapping-score case without shipping user reports.
$guide=[pscustomobject]@{
    Phase='Decision';Device=[pscustomobject]@{Current=600};TargetWatts=540
    Verdict=[pscustomobject]@{
        Title='Inconclusive: score ranges overlap';Recommendation='Restore original limit recommended.'
        BeforeMedian=5302.92;AfterMedian=5311.57;PercentChange=0.163117636321119;Detail='Comparison details'
    }
}
$before=$guide|ConvertTo-Json -Depth 8
$view=Get-PCGuidePresentation $guide $true
Assert ($view.Stage -match 'choose Keep or Restore' -and $view.NextAction -match 'has not changed your settings') 'A recommendation was presented as a completed action'
Assert ($view.RestoreLabel -eq 'Restore 600 W' -and $view.KeepLabel -eq 'Keep 540 W') 'Decision actions omit the reviewed wattages'
Assert ($view.BeforeScore -eq '5302.92' -and $view.AfterScore -eq '5311.57' -and $view.Change -eq '+0.16%') 'Measured comparison changed during formatting'
Assert ($view.ResultTitle -match 'Inconclusive' -and $view.Tone -eq 'Attention') 'A small positive change was shown as proven success'
Assert (($guide|ConvertTo-Json -Depth 8) -eq $before) 'Presentation mutated saved workflow data'
$guide.Phase='Restored';$view=Get-PCGuidePresentation $guide $false
Assert ($view.Stage -eq 'Original limit restored: 600 W' -and $view.NextAction -match 'read-back verified') 'Verified restoration is not the primary status'
Assert ($view.NextAction -match 'not a live GPU reading' -and $view.RecommendationLabel -eq 'RECORDED TEST RECOMMENDATION') 'Saved results can be mistaken for live state or an outstanding decision'
$view=Get-PCGuidePresentation $guide $true
Assert ($view.Tone -eq 'Warning' -and $view.Stage -notmatch 'restored:' -and $view.NextAction -match 'Tuning') 'Pending recovery was hidden by an old restored result'
$guide.Phase='Kept';$view=Get-PCGuidePresentation $guide $true
Assert ($view.Stage -match 'chose to keep 540 W' -and $view.NextAction -match 'Restore 600 W remains available') 'Keep hid the restore path'
$guide.Phase='RecoveryRequired';$view=Get-PCGuidePresentation $guide $true
Assert ($view.Tone -eq 'Warning' -and $view.NextAction -match 'has not been verified') 'Failed recovery claimed verified restoration'
$guide.Phase='Decision';$view=Get-PCGuidePresentation $guide $false
Assert ($view.Tone -eq 'Warning' -and $view.Recovery -match 'record is missing') 'Missing recovery record was hidden'
$view=Get-PCGuidePresentation $guide $false 'Unreadable saved file'
Assert ($view.Stage -match 'could not be loaded' -and $view.Tone -eq 'Warning') 'Unreadable state claimed a completed action'
$view=Get-PCGuidePresentation $null
Assert ($view.BeforeScore -eq '--' -and $view.AfterScore -eq '--' -and $view.Change -eq '--') 'Untested scores were invented'
$guide.Verdict.BeforeMedian=$null;$guide.Verdict.AfterMedian=[double]::NaN;$guide.Verdict.PercentChange=[double]::PositiveInfinity
$view=Get-PCGuidePresentation $guide $true
Assert ($view.BeforeScore -eq '--' -and $view.AfterScore -eq '--' -and $view.Change -eq '--') 'Missing or invalid scores were presented as measurements'
'PASS: recommendation versus completed action, exact wattages, saved versus live state, recovery warnings, honest score formatting and immutable presentation'
