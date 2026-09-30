$ErrorActionPreference='Stop'
function Assert($ok,$message){if(-not $ok){throw $message}}
function Test-PCClockGuideLocked {$script:locked}
function Confirm($message){$true}
function Get-ActivePlan {'test-plan'}
function Start-Task($kind){$script:started=$kind;$script:job=[pscustomobject]@{State='Running'}}
function Save-JsonAtomic($value,$path){$value|ConvertTo-Json|Set-Content $path}
function Show-Error($text){throw $text}
$ui=@{};foreach($n in 'Endurance5','Endurance10','EnduranceStop','EnduranceStatus'){$c=[pscustomobject]@{IsEnabled=$false;Text=''};$c|Add-Member ScriptMethod Add_Click {param($handler)};$ui[$n]=$c}
$dataDir=Join-Path ([IO.Path]::GetTempPath()) ('pc-endurance-ui-'+[guid]::NewGuid());$null=New-Item $dataDir -ItemType Directory
try{
 $script:snapshot=[pscustomobject]@{};$script:locked=$false;$script:job=$null;$script:updateJob=$null;$script:guide=$null;$script:clockActionBusy=$false
 . "$PSScriptRoot/../GpuEnduranceUI.ps1"
 Assert $ui.Endurance5.IsEnabled 'Idle scanned app cannot start'
 $script:locked=$true;Start-PCGpuEnduranceUI 5;Assert (-not $script:started) 'Guided lock bypassed'
 $script:locked=$false;Start-PCGpuEnduranceUI 5;Assert ($script:started -eq 'endurance5') 'Wrong task dispatched'
 Assert ((Get-Content $script:endurancePath -Raw|ConvertFrom-Json).State -eq 'Running') 'Running journal missing'
 $script:job=$null
 . "$PSScriptRoot/../GpuEnduranceUI.ps1"
 Assert ((Get-Content $script:endurancePath -Raw|ConvertFrom-Json).State -eq 'Interrupted') 'Restart claimed completion'
 Save-PCGpuEnduranceStatus 'Stopped' 'Partial result';. "$PSScriptRoot/../GpuEnduranceUI.ps1"
 Assert ($ui.EnduranceStatus.Text -eq 'Partial result') 'Saved outcome lost'
 $script:snapshot=$null;Refresh-PCGpuEnduranceUI;Assert (-not $ui.Endurance5.IsEnabled) 'Unscanned start allowed'
 # Exercise the actual app Start-Task ordering, without executing its background worker.
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../PC-Insight.ps1'),[ref]$null,[ref]$null)
 $start=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-Task'},$true)
 Invoke-Expression $start.Extent.Text
 function Refresh-PCCpuTuningUI {}
 function Set-Busy($busy){Refresh-PCGpuEnduranceUI}
 function Get-PCTuningCapabilities {$null}
 function Start-Job {param($ArgumentList,$ScriptBlock);[pscustomobject]@{State='Running'}}
 foreach($n in 'TestProgress','ProgressLabel','Status'){$ui[$n]=[pscustomobject]@{Value=0;Text=''}}
 foreach($n in 'TemperatureChart','UsageChart'){$ui[$n]=[pscustomobject]@{Children=[Collections.ArrayList]::new()}}
 $script:stopPath=Join-Path $dataDir 'stop';$script:snapshot=[pscustomobject]@{};$script:job=$null
 Start-Task 'endurance5'
 Assert ($ui.EnduranceStop.IsEnabled -and -not $ui.Endurance5.IsEnabled -and -not $ui.Endurance10.IsEnabled) 'Stop must enable AFTER Start-Job returns; duration buttons must lock'
 $script:job=$null;Set-Busy $false
 Assert (-not $ui.EnduranceStop.IsEnabled -and $ui.Endurance5.IsEnabled) 'Idle button states not restored'
 'PASS: real endurance UI handlers with mocked controls, locks, dispatch, running journal and no-write restart recovery'
}finally{Remove-Item $dataDir -Recurse -Force}
