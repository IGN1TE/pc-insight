# Inventory-based guidance only. No CPU register, voltage, firmware or power-limit writes.
function Get-PCCpuTuningReadiness($Snapshot){
    $cpus=@($Snapshot.CPU|Where-Object {$_ -and $_.Name});$boards=@($Snapshot.Board|Where-Object {$_});$bios=@($Snapshot.BIOS|Where-Object {$_})
    $name=($cpus.Name -join '; ');$vendor='Unknown';$candidate=$false;$url=$null
    $reason='Scan PC to collect processor, board and BIOS inventory. CPU control support is not established.'
    if($cpus.Count -gt 1){$reason='Multiple processor records found. No single-CPU tuning route is inferred.'}
    elseif($cpus.Count -eq 1){
        if($cpus[0].Manufacturer -match 'Intel' -or $name -match 'Intel'){
            $vendor='Intel';$url='https://www.intel.com/content/www/us/en/support/articles/000057552/processors/intel-core-processors.html'
            $candidate=$name -match '(?i)\b(?:i[3579]-\d{4,5}(?:KF|KS|K|XE|X|HK)|Ultra\s+[579]\s+\d{3}(?:KF|K))\b'
            $reason=if($candidate){'Unlocked-style Intel model name detected. This is a candidate for checking Intel XTU requirements, not verified write support. The exact CPU, motherboard, BIOS and XTU version must all be supported.'}else{'No recognized unlocked Intel desktop model pattern. This is not a definitive locked/unlocked determination. Check the exact CPU against Intel requirements; controls remain unavailable.'}
        }elseif($cpus[0].Manufacturer -match 'AMD|Advanced Micro Devices' -or $name -match '\bAMD\b'){
            $vendor='AMD';$url='https://www.amd.com/en/products/software/ryzen-master.html'
            $reason='AMD processor identified. Check the exact model and motherboard against current Ryzen Master requirements. Ryzen, X3D or Threadripper branding alone does not establish which controls are supported.'
        }else{$reason='Processor vendor is unknown or unsupported by this readiness guide. No tuning capability is inferred.'}
    }
    $board=($boards|ForEach-Object {(@($_.Manufacturer,$_.Product)|Where-Object {$_}) -join ' '}) -join '; '
    $firmware=($bios.SMBIOSBIOSVersion -join '; ')
    $rows=@(
        [pscustomobject]@{Control='CPU multiplier / frequency';Availability='Unavailable in PC Insight';Detail='No validated vendor write/readback adapter is integrated.'}
        [pscustomobject]@{Control='CPU voltage / undervolt';Availability='Unavailable in PC Insight';Detail='No voltage control, range detection or original-value restoration is implemented.'}
        [pscustomobject]@{Control='CPU package power limits';Availability='Use Detect CPU power limits below';Detail='The limited i7-13700K preview can lower PL1 / PL2 after a live probe, save the originals and verify restoration. Inventory alone does not enable writes.'}
        [pscustomobject]@{Control='Three-run CPU measurement';Availability=$(if($cpus.Count -eq 1){'Available; sensor checks at start'}else{'Scan one CPU first'});Detail='Three monitored 60-second SHA-256 runs with cooldowns; temperature required. Not a comprehensive CPU or stability test.'}
        [pscustomobject]@{Control='Windows power-plan selection';Availability='Available on Optimize';Detail='Select and restore an installed Windows power plan. This does not set CPU multipliers or voltage.'}
    )
    [pscustomobject]@{Schema=1;Generated=(Get-Date).ToString('o');SnapshotTimestamp=$Snapshot.Timestamp;CPUName=$name;Vendor=$vendor;Board=$board;BIOS=$firmware;ProcessorRecords=$cpus.Count;ModelCandidate=$candidate;CanWrite=$false;CanBenchmark=($cpus.Count -eq 1);Reason=$reason;VendorRequirementsUrl=$url;Controls=$rows;Limitations='Inventory snapshot only, not a live hardware-control probe. No BIOS lock, voltage range, multiplier range, thermal headroom or vendor-tool installation is established. This inventory report applies no settings. The separate CPU power-limit controls perform a live check before any reviewed change.'}
}
function Format-PCCpuTuningReadiness($Report){
    $cpu=if($Report.CPUName){$Report.CPUName}else{'Unavailable — Scan PC first'}
    $board=if($Report.Board){$Report.Board}else{'Unavailable'};$bios=if($Report.BIOS){$Report.BIOS}else{'Unavailable'}
    "CPU: $cpu`nMotherboard (firmware-reported): $board`nBIOS version: $bios`nInventory collected: $($Report.SnapshotTimestamp)`n`n$($Report.Reason)`n`n$($Report.Limitations)"
}
