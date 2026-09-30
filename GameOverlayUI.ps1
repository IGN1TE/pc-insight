# Loaded after the main controls. The hotkey and capture are opt-in for this app session.
$script:overlayWindow=$null;$script:overlayUI=@{};$script:overlaySensorJob=$null
$script:overlayFrame=$null;$script:overlayCapture=$null;$script:overlayTargetId=0
$script:overlayFpsIssue=''
$script:overlayTargetName='';$script:lastOverlayFpsReport=$null
$script:overlaySource=$null;$script:overlayHook=$null;$script:overlayHotkeyAdapter=$null;$script:overlayHotkey=$false
$script:overlayStopPath=Join-Path $dataDir ('overlay-stop-'+[guid]::NewGuid().ToString('N')+'.signal')
$script:overlayTimer=[Windows.Threading.DispatcherTimer]::new()
$script:overlayTimer.Interval=[timespan]::FromMilliseconds(500)
function Save-PCOverlayFpsStatus {
    if(-not $script:overlayCapture){return}
    try{
        $diagnostic=$script:overlayCapture.GetDiagnostics()
        $reading=$script:overlayCapture.Read()
        # Retain meaningful captures when focus switches, including processes that fail immediately.
        if($diagnostic.ElapsedSeconds -lt 3 -and -not $diagnostic.ProcessExited -and $null -eq $reading.Fps){return}
        $script:lastOverlayFpsReport=New-PCOverlayFpsReport $diagnostic ($script:overlayTargetName+'.exe') $reading.Status $script:isAdministrator $script:appVersion
        $ui.LastFpsCapture.Text='Last capture: '+$script:lastOverlayFpsReport.TargetProcess+' | '+$reading.Status
        $ui.ExportFpsDetails.IsEnabled=$true
    }catch{}
}
function Stop-PCOverlayCapture {
    Save-PCOverlayFpsStatus
    if($script:overlayCapture){try{$script:overlayCapture.Dispose()}catch{};$script:overlayCapture=$null}
    $script:overlayTargetId=0
    $script:overlayFpsIssue=''
}
function Hide-PCGameOverlay([string]$Reason='Overlay hidden. Press Ctrl+Alt+O to show it again when the hotkey is enabled.') {
    $script:overlayTimer.Stop()
    if($script:overlayWindow){$script:overlayWindow.Hide()}
    Stop-PCOverlayCapture
    if($script:overlaySensorJob){
        try{
            Set-Content -LiteralPath $script:overlayStopPath -Value 'stop'
            $null=Wait-Job $script:overlaySensorJob -Timeout 2
        }catch{
            # A full/unwritable data folder must not leave the sampler running.
        }finally{
            if($script:overlaySensorJob.State -notin @('Completed','Failed','Stopped')){Stop-Job $script:overlaySensorJob -ErrorAction SilentlyContinue}
            Remove-Job $script:overlaySensorJob -Force -ErrorAction SilentlyContinue
            $script:overlaySensorJob=$null
        }
    }
    Remove-Item -LiteralPath $script:overlayStopPath -ErrorAction SilentlyContinue
    $script:overlayFrame=$null
    $ui.ToggleOverlay.Content='Show overlay'
    $ui.OverlayStatus.Text=$Reason
}
function Set-PCOverlayHotkey([bool]$Enabled) {
    if($Enabled){
        if($script:overlayHotkey){return}
        Initialize-PCOverlayNative
        $handle=[Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
        $script:overlaySource=[Windows.Interop.HwndSource]::FromHwnd($handle)
        if(-not [PCInsightOverlayNative]::RegisterHotKey($handle,0x5043,0x4003,0x4F)){
            throw 'Ctrl+Alt+O is already in use. Close the conflicting hotkey tool, or use Show overlay here.'
        }
        $script:overlayHotkey=$true
        $script:overlayHotkeyAdapter=[PCInsightOverlayHotkey]::new(0x5043,[Action]{
            try{Toggle-PCGameOverlay}catch{$ui.OverlayStatus.Text=$_.Exception.Message}
        })
        $script:overlayHook=[Delegate]::CreateDelegate([Windows.Interop.HwndSourceHook],$script:overlayHotkeyAdapter,'HandleMessage')
        $script:overlaySource.AddHook($script:overlayHook)
        $ui.OverlayStatus.Text='Hotkey ready. Focus your game and press Ctrl+Alt+O.'
    }else{
        if($script:overlayHotkey -and $script:overlaySource){
            $null=[PCInsightOverlayNative]::UnregisterHotKey($script:overlaySource.Handle,0x5043)
            if($script:overlayHook){$script:overlaySource.RemoveHook($script:overlayHook)}
        }
        $script:overlayHotkey=$false;$script:overlayHook=$null;$script:overlayHotkeyAdapter=$null;$script:overlaySource=$null
    }
    if($script:overlayWindow){$script:overlayUI.OverlayHint.Text=if($script:overlayHotkey){'Ctrl+Alt+O to hide'}else{'Hide from PC Insight > Game overlay'}}
}
function Show-PCGameOverlay {
    if($script:job -or $script:updateJob -or $script:clockActionBusy -or $script:clockTrialJob -or ($script:guide -and $script:guide.Phase -in @('RunningBaseline','Review','Applying','RunningAfter','Decision','RecoveryRequired'))){
        $ui.OverlayStatus.Text='Finish the active test, update or guided decision before showing the game overlay.';return
    }
    try{
        Initialize-PCOverlayNative
        $script:overlayPresentMon=Get-PCPresentMonPath
        if(-not $script:overlayWindow){
            [xml]$overlayXaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GameOverlay.xaml') -Raw -Encoding UTF8
            $script:overlayWindow=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($overlayXaml))
            foreach($name in 'OverlayCpu','OverlayGpu','OverlayGpuLabel','OverlayFps','OverlayTarget','OverlayHint'){$script:overlayUI[$name]=$script:overlayWindow.FindName($name)}
        }
        $overlayHandle=[Windows.Interop.WindowInteropHelper]::new($script:overlayWindow).EnsureHandle()
        [PCInsightOverlayNative]::MakePassive($overlayHandle)
        Remove-Item -LiteralPath $script:overlayStopPath -ErrorAction SilentlyContinue
        $script:overlayFrame=$null
        $script:overlaySensorJob=Start-Job -ArgumentList $PSScriptRoot,$script:overlayStopPath,$PID,(Get-Process -Id $PID).StartTime.Ticks -ScriptBlock {
            param($root,$stopPath,$ownerId,$ownerStart)
            $ErrorActionPreference='Stop'
            . (Join-Path $root 'NativeSensors.ps1')
            try{
                Initialize-PCNativeSensors
                while(-not(Test-Path -LiteralPath $stopPath)){
                    try{$owner=Get-Process -Id $ownerId -ErrorAction Stop;if($owner.StartTime.Ticks -ne $ownerStart){break}}catch{break}
                    [pscustomobject]@{Kind='Frame';Value=(Get-PCNativeFrame)}
                    for($i=0;$i -lt 10 -and -not(Test-Path -LiteralPath $stopPath);$i++){Start-Sleep -Milliseconds 100}
                }
            }catch{[pscustomobject]@{Kind='Issue';Value=$_.Exception.Message}}finally{Close-PCNativeSensors}
        }
        foreach($name in 'OverlayCpu','OverlayGpu','OverlayFps'){$script:overlayUI[$name].Text='--'}
        $script:overlayUI.OverlayTarget.Text='Focus your game'
        $script:overlayUI.OverlayHint.Text=if($script:overlayHotkey){'Ctrl+Alt+O to hide'}else{'Hide from PC Insight > Game overlay'}
        $script:overlayWindow.Show()
        $bounds=[System.Windows.Forms.Screen]::FromHandle([PCInsightOverlayNative]::GetForegroundWindow()).Bounds
        $null=[PCInsightOverlayNative]::SetWindowPos($overlayHandle,[IntPtr](-1),($bounds.Left+18),($bounds.Top+18),0,0,0x0011)
        $ui.ToggleOverlay.Content='Hide overlay'
        $ui.OverlayStatus.Text='Overlay active. Focus your game; temperature and FPS readings may take a few seconds.'
        $script:overlaySensorIssue=''
        $script:overlayTimer.Start()
    }catch{
        $reason=$_.Exception.Message
        Hide-PCGameOverlay ('Overlay could not start: '+$reason)
    }
}
function Toggle-PCGameOverlay {
    if($script:overlayWindow -and $script:overlayWindow.IsVisible){Hide-PCGameOverlay}else{Show-PCGameOverlay}
}
function Close-PCGameOverlay {
    Hide-PCGameOverlay 'Overlay stopped.'
    Set-PCOverlayHotkey $false
    if($script:overlayWindow){$script:overlayWindow.Close();$script:overlayWindow=$null}
}
$script:overlayTimer.Add_Tick({
    try{
        if(-not $script:overlayWindow.IsVisible){return}
        if($script:overlaySensorJob){
            foreach($item in @(Receive-Job $script:overlaySensorJob -ErrorAction SilentlyContinue)){
                if($item.Kind -eq 'Frame'){$script:overlayFrame=$item.Value}
                elseif($item.Kind -eq 'Issue'){$script:overlaySensorIssue=[string]$item.Value}
            }
            if($script:overlaySensorJob.State -eq 'Failed' -and -not $script:overlaySensorIssue){$script:overlaySensorIssue='Temperature reader stopped. Hide and show the overlay to retry.'}
        }
        $temperature=Get-PCOverlayTemperatures $script:overlayFrame
        $script:overlayUI.OverlayCpu.Text=$temperature.CPU
        $script:overlayUI.OverlayGpu.Text=$temperature.GPU
        $script:overlayUI.OverlayGpuLabel.Text=$temperature.GPULabel
        $foreground=[PCInsightOverlayNative]::GetForegroundWindow()
        [uint32]$targetProcessId=0
        $null=[PCInsightOverlayNative]::GetWindowThreadProcessId($foreground,[ref]$targetProcessId)
        $targetName=''
        if($targetProcessId -gt 0 -and $targetProcessId -ne $PID){
            try{$target=Get-Process -Id $targetProcessId -ErrorAction Stop;$targetName=$target.ProcessName;$target.Dispose()}catch{$targetProcessId=0}
        }else{$targetProcessId=0}
        if($targetName -match '^(explorer|dwm|ShellExperienceHost|StartMenuExperienceHost|SearchHost|LockApp)$'){$targetProcessId=0}
        if($targetProcessId -ne $script:overlayTargetId -or ($script:overlayCapture -and $script:overlayCapture.FinishedInterval)){
            Stop-PCOverlayCapture
            $script:overlayTargetId=$targetProcessId
            $script:overlayTargetName=$targetName
            $bounds=[System.Windows.Forms.Screen]::FromHandle($foreground).Bounds
            $handle=[Windows.Interop.WindowInteropHelper]::new($script:overlayWindow).Handle
            $null=[PCInsightOverlayNative]::SetWindowPos($handle,[IntPtr](-1),($bounds.Left+18),($bounds.Top+18),0,0,0x0011)
            if($targetProcessId -gt 0){
                try{$script:overlayCapture=[PCInsightFpsCapture]::new($script:overlayPresentMon,$targetProcessId)}
                catch{$script:overlayFpsIssue='FPS unavailable: '+$_.Exception.Message}
            }
        }
        $fpsStatus=if($script:overlayFpsIssue){$script:overlayFpsIssue}else{'Focus the game window to measure FPS.'}
        $script:overlayUI.OverlayFps.Text='--'
        $script:overlayUI.OverlayTarget.Text='Focus your game'
        if($script:overlayFpsIssue){$script:overlayUI.OverlayTarget.Text=$targetName+'.exe | FPS unavailable'}
        if($script:overlayCapture){
            $reading=$script:overlayCapture.Read();$fpsStatus=$reading.Status
            if($null -ne $reading.Fps){$script:overlayUI.OverlayFps.Text=('{0:0}' -f $reading.Fps)}
            $diagnostic=$script:overlayCapture.GetDiagnostics()
            $script:overlayUI.OverlayTarget.Text=$targetName+'.exe'+$(if($script:overlayCapture.HasExited){' | FPS unavailable'}elseif($null -eq $reading.Fps -and $diagnostic.ElapsedSeconds -ge 10){' | no FPS data'}elseif($null -eq $reading.Fps){' | waiting for FPS'}else{''})
            Save-PCOverlayFpsStatus
        }
        $sensorIssue=if($script:overlaySensorIssue){$script:overlaySensorIssue}else{$temperature.Issue}
        $ui.OverlayStatus.Text='Overlay active. '+$fpsStatus+$(if($sensorIssue){' | '+$sensorIssue}else{''})
    }catch{
        $reason=$_.Exception.Message
        Hide-PCGameOverlay ('Overlay stopped: '+$reason)
    }
})
$ui.EnableOverlayHotkey.Add_Checked({
    try{Set-PCOverlayHotkey $true}catch{
        $reason=$_.Exception.Message
        $ui.EnableOverlayHotkey.IsChecked=$false
        $ui.OverlayStatus.Text=$reason
    }
})
$ui.EnableOverlayHotkey.Add_Unchecked({Set-PCOverlayHotkey $false;Hide-PCGameOverlay 'Hotkey disabled. You can still use Show overlay here.'})
$ui.ToggleOverlay.Add_Click({Toggle-PCGameOverlay})
$ui.ExportFpsDetails.Add_Click({
    try{
        Save-PCOverlayFpsStatus
        if(-not $script:lastOverlayFpsReport){return}
        $dialog=[Microsoft.Win32.SaveFileDialog]::new()
        $dialog.Filter='JSON FPS details (*.json)|*.json';$dialog.FileName='PC-Insight-FPS-diagnostic.json'
        if($dialog.ShowDialog() -eq $true){Save-JsonAtomic $script:lastOverlayFpsReport $dialog.FileName}
    }catch{Show-Error $_.Exception.Message}
})
$window.Add_Closed({Close-PCGameOverlay})
