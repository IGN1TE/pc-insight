function Invoke-PowerCfg([string[]]$Arguments) {
    $result = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Windows could not complete the power-plan request: $($result -join ' ')" }
    $result -join "`n"
}
function Get-ActivePlan {
    $raw = Invoke-PowerCfg @('/getactivescheme')
    $match = [regex]::Match($raw, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if (-not $match.Success) { throw 'Windows did not return a power-plan identifier.' }
    $match.Value.ToLowerInvariant()
}
function Get-AvailablePlans {
    $raw = Invoke-PowerCfg @('/list')
    @([regex]::Matches($raw, '(?im)([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\s+\((.+)\)') | ForEach-Object {
        [pscustomobject]@{ ID = $_.Groups[1].Value.ToLowerInvariant(); Name = $_.Groups[2].Value }
    })
}
function Set-VerifiedPlan([string]$id) {
    if ($id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') { throw 'Invalid plan identifier.' }
    $plans = @(Get-AvailablePlans)
    if ($id -notin $plans.ID) { throw 'This plan is no longer installed. Open Windows power settings to choose an available plan.' }
    $null = Invoke-PowerCfg @('/setactive', $id)
    if ((Get-ActivePlan) -ne $id) { throw 'Windows did not confirm the requested plan. Check Windows power settings.' }
}
function Save-JsonAtomic($value, [string]$path) {
    $temp = "$path.tmp"
    $value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop
}

function Expand-PCHistory($records) {
    foreach ($record in $records) {
        if ($null -eq $record) { continue }
        if ($record.Test) { $record }
        elseif ($null -ne $record.value) { Expand-PCHistory $record.value }
        elseif ($record -is [array]) { Expand-PCHistory $record }
    }
}
