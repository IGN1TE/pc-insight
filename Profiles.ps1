function Save-PCNamedProfile([string]$Folder,[string]$Name,$Baseline) {
    $Name=$Name.Trim()
    if($Name.Length -lt 1 -or $Name.Length -gt 60 -or $Name -match '[\x00-\x1f]'){throw 'Use a profile name from 1 to 60 characters, without control characters.'}
    if(-not $Baseline -or $Baseline.Schema -ne 1 -or -not $Baseline.Created){throw 'Save a baseline first, then name it.'}
    $null=New-Item -ItemType Directory -Path $Folder -Force
    $id=[guid]::NewGuid().ToString()
    $profile=[pscustomobject]@{Schema=1;ID=$id;Name=$Name;Saved=(Get-Date).ToString('o');Baseline=$Baseline}
    Save-JsonAtomic $profile (Join-Path $Folder ($id+'.json'))
    $profile
}
function Get-PCNamedProfiles([string]$Folder) {
    if(-not (Test-Path -LiteralPath $Folder)){return}
    foreach($file in Get-ChildItem -LiteralPath $Folder -Filter '*.json' -File){
        try {
            if($file.BaseName -notmatch '^[a-f0-9-]{36}$'){continue}
            $p=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if($p.Schema -ne 1 -or $p.ID -ne $file.BaseName -or -not $p.Baseline.Created){continue}
            [pscustomobject]@{ID=$p.ID;Name=$p.Name;Saved=$p.Saved;Label="$($p.Name) · $($p.Saved)"}
        }catch{Write-Warning "Could not read saved profile $($file.Name). File retained."}
    }
}
function Read-PCNamedProfile([string]$Folder,[string]$ID) {
    $parsed=[guid]::Empty
    if(-not [guid]::TryParseExact($ID,'D',[ref]$parsed)){throw 'Invalid profile identity.'}
    $p=Get-Content -LiteralPath (Join-Path $Folder ($parsed.ToString()+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
    if($p.Schema -ne 1 -or $p.ID -ne $ID -or $p.Baseline.Schema -ne 1 -or -not $p.Baseline.Created){throw 'Saved profile is invalid.'}
    $p
}
