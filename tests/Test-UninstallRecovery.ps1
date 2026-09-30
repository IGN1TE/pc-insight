# Exercise the real recovery guard without running the uninstaller or touching installed files.
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Uninstall.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Uninstaller contains parse errors'}
$guard=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PCUninstallRecovery'},$true)
if(-not $guard){throw 'Recovery guard is missing'}
. ([scriptblock]::Create($guard.Extent.Text))
$folder=Join-Path ([IO.Path]::GetTempPath()) ('pc-uninstall-recovery-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $folder
try{
    Assert-PCUninstallRecovery $folder
    foreach($name in @('gpu-clock-restore.json','gpu-power-restore.json','restore.json')){
        $record=Join-Path $folder $name
        # Even a corrupt journal must block removal of the recovery UI.
        [IO.File]::WriteAllText($record,'{invalid recovery record')
        $blocked=$false
        try{Assert-PCUninstallRecovery $folder}catch{$blocked=$_.Exception.Message -like '*recovery record*'}
        if(-not $blocked -or -not [IO.File]::Exists($record)){throw ('Uninstall did not preserve and block '+$name)}
        [IO.File]::Delete($record)
    }
    [IO.File]::WriteAllText((Join-Path $folder 'sessions.json'),'[]')
    Assert-PCUninstallRecovery $folder
    'PASS: pending clock, GPU power and Windows plan recovery block uninstall; corrupt records remain; ordinary sessions do not block.'
}finally{
    foreach($file in [IO.Directory]::GetFiles($folder)){[IO.File]::Delete($file)}
    [IO.Directory]::Delete($folder,$false)
}
