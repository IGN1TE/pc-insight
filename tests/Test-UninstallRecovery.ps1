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
    foreach($name in @('cpu-power-restore.json','gpu-clock-restore.json','gpu-power-restore.json','restore.json')){
        $record=Join-Path $folder $name
        # Valid and corrupt journals must both block removal of the recovery UI.
        foreach($contents in @('{"Schema":1,"State":"Applied"}','{invalid recovery record')){
            [IO.File]::WriteAllText($record,$contents)
            $blocked=$false;$message=''
            try{Assert-PCUninstallRecovery $folder}catch{$message=$_.Exception.Message;$blocked=$message -like '*recovery record*'}
            if(-not $blocked -or [IO.File]::ReadAllText($record) -cne $contents){throw ('Uninstall did not preserve and block '+$name)}
            if($name -eq 'cpu-power-restore.json' -and $message -notlike '*Restore saved CPU limits*'){throw 'CPU recovery block does not explain how to continue'}
        }
        [IO.File]::Delete($record)
    }
    [IO.File]::WriteAllText((Join-Path $folder 'sessions.json'),'[]')
    Assert-PCUninstallRecovery $folder
    'PASS: pending CPU power, GPU clock, GPU power and Windows plan recovery block uninstall; corrupt records remain; ordinary sessions do not block.'
}finally{
    foreach($file in [IO.Directory]::GetFiles($folder)){[IO.File]::Delete($file)}
    [IO.Directory]::Delete($folder,$false)
}
