# Run the production recovery guard without launching an installer or replacing app files.
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Install.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Installer contains parse errors'}
$guard=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PCInstallRecovery'},$true)
if(-not $guard){throw 'Installer CPU recovery guard is missing'}
. ([scriptblock]::Create($guard.Extent.Text))
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pc-install-recovery-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $folder
try{
    Assert-PCInstallRecovery $folder
    $record=Join-Path $folder 'cpu-power-restore.json'
    foreach($contents in @('{"Schema":1,"State":"Applied"}','{invalid recovery record')){
        [IO.File]::WriteAllText($record,$contents)
        $blocked=$false
        try{Assert-PCInstallRecovery $folder}catch{$blocked=$_.Exception.Message -like '*Restore saved CPU limits*'}
        if(-not $blocked -or [IO.File]::ReadAllText($record) -cne $contents){throw 'Installer did not block replacement and retain the CPU recovery record'}
    }
    [IO.File]::Delete($record)
    # Existing GPU/plan recovery and saved results retain their prior installer behavior.
    foreach($name in @('gpu-clock-restore.json','gpu-power-restore.json','restore.json','sessions.json')){
        [IO.File]::WriteAllText((Join-Path $folder $name),'{}')
    }
    Assert-PCInstallRecovery $folder
    'PASS: CPU recovery blocks install/update; corrupt records remain unchanged; no CPU journal and existing GPU/plan records preserve prior behavior.'
}finally{
    foreach($file in [IO.Directory]::GetFiles($folder)){[IO.File]::Delete($file)}
    [IO.Directory]::Delete($folder,$false)
}
