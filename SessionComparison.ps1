# Pure saved-data comparison. Does not query hardware or change settings.
function Get-PCComparisonNumber($Value) {
    $text=ConvertTo-PCInvariantNumber $Value
    if($text -ne ''){[double]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)}
}
function New-PCComparisonRow([string]$Metric,$Before,$After,[string]$Unit,[bool]$AllowDelta=$true,[string]$Coverage='') {
    $a=Get-PCComparisonNumber $Before;$b=Get-PCComparisonNumber $After
    $delta=$null;$percent=$null
    if($AllowDelta -and $null -ne $a -and $null -ne $b){
        $candidate=$b-$a
        if(-not [double]::IsInfinity($candidate)){$delta=$candidate}
        if($a -gt 0){
            $candidate=100*($b/$a-1)
            if(-not [double]::IsInfinity($candidate) -and -not [double]::IsNaN($candidate)){$percent=$candidate}
        }
    }
    [pscustomobject]@{
        Metric=$Metric;Before=$a;After=$b;Unit=$Unit;Delta=$delta;PercentChange=$percent
        BeforeText=if($null -eq $a){'Unavailable'}else{'{0:N1} {1}' -f $a,$Unit}
        AfterText=if($null -eq $b){'Unavailable'}else{'{0:N1} {1}' -f $b,$Unit}
        ChangeText=if($null -eq $delta){'Not compared'}else{'{0:+0.0;-0.0;0.0} {1}' -f $delta,$Unit}
        Coverage=$Coverage
    }
}
function Get-PCSessionComparison($Before,$After) {
    if(-not $Before -or -not $After){return}
    $reasons=[Collections.Generic.List[string]]::new()
    $notes=[Collections.Generic.List[string]]::new()
    if([object]::ReferenceEquals($Before,$After) -or ($Before.Timestamp -and $Before.Timestamp -eq $After.Timestamp -and $Before.Test -eq $After.Test)){$reasons.Add('Choose two different sessions.')}
    $knownTests=@('SHA256-1MiB-parallel-v2','SHA256-1MiB-parallel-60s-v1','RAM-copy-128MiB-20s-v1','OpenGL-1280x720-256shader-b8-w5-30s-v2')
    if($Before.Test -ne $After.Test){$reasons.Add('Test types or versions differ.')}
    elseif($Before.Test -notin $knownTests){$reasons.Add('These sessions do not have a supported benchmark score comparison.')}
    foreach($session in @($Before,$After)){
        if($session.Completed -isnot [bool] -or -not $session.Completed -or $session.StopReason){$reasons.Add('Both tests must have completed successfully.');break}
    }
    $fields=@('CPUName','Runtime','Workers')
    if($Before.Test -like 'OpenGL-*' -or $After.Test -like 'OpenGL-*'){$fields+=@('Renderer','DriverVersion','WarmupSeconds')}
    if($Before.Test -like 'RAM-*' -or $After.Test -like 'RAM-*'){$fields+=@('MemoryConfig','BufferMiB')}
    foreach($field in $fields){
        if([string]::IsNullOrWhiteSpace([string]$Before.$field) -or [string]::IsNullOrWhiteSpace([string]$After.$field)){$reasons.Add("Missing $field metadata.")}
        elseif([string]$Before.$field -cne [string]$After.$field){$reasons.Add("$field differs.")}
    }
    foreach($session in @($Before,$After)){
        $workers=Get-PCComparisonNumber $session.Workers
        if($null -eq $workers -or $workers -le 0 -or $workers -ne [math]::Floor($workers)){$reasons.Add('Worker count is missing or invalid.')}
    }
    $durationA=Get-PCComparisonNumber $Before.Seconds;$durationB=Get-PCComparisonNumber $After.Seconds
    if($null -eq $durationA -or $durationA -le 0 -or $null -eq $durationB -or $durationB -le 0){$reasons.Add('Recorded test duration is missing or invalid.')}
    elseif([math]::Abs($durationB-$durationA) -gt [math]::Max(2,0.1*[math]::Min($durationA,$durationB))){$reasons.Add('Recorded durations differ by more than 10% (with a two-second tolerance).')}
    $a=Get-PCComparisonNumber (Get-PCResultRate $Before);$b=Get-PCComparisonNumber (Get-PCResultRate $After)
    if($null -eq $a -or $a -le 0 -or $null -eq $b -or $b -le 0){$reasons.Add('A positive, finite score is missing.')}
    if(-not $Before.Plan -or -not $After.Plan){$notes.Add('Power-plan information is incomplete.')}
    elseif($Before.Plan -ne $After.Plan){$notes.Add('Power plan changed between these sessions.')}
    else{$notes.Add('Power plan is the same.')}
    $beforePower=Get-PCComparisonPowerContext $Before.PowerStateAtStart
    $afterPower=Get-PCComparisonPowerContext $After.PowerStateAtStart
    $notes.Add("GPU power limits at start: A $beforePower; B $afterPower.")
    $notes.Add('Change means B minus A. One pair of runs does not establish an improvement; repeat equivalent tests to check variation. Benchmark throughput is not game FPS.')
    $notes.Add('Sensor changes are descriptive sample statistics for matching sensor identities. Only retained samples count; missing readings and frames with issues are excluded. Averages are not time-weighted. Different workloads, durations or sample coverage can change the results.')
    $reasons=@($reasons|Select-Object -Unique)
    $comparable=$reasons.Count -eq 0
    $rows=[Collections.Generic.List[object]]::new()
    $score=New-PCComparisonRow 'Benchmark throughput' $a $b (Get-PCResultUnit $After) $comparable
    # Different workloads can have different units; preserve both units even when comparison is blocked.
    if($null -ne $a){$score.BeforeText='{0:N1} {1}' -f $a,(Get-PCResultUnit $Before)}
    if($comparable -and $null -ne $score.PercentChange){$score.ChangeText+=' ({0:+0.0;-0.0;0.0}%)' -f $score.PercentChange}
    $rows.Add($score)
    $rows.Add((New-PCComparisonRow 'Recorded duration' $Before.Seconds $After.Seconds 's'))
    $beforeDetails=@{};$afterDetails=@{}
    foreach($detail in @(Get-PCSessionSensorDetails $Before)){$beforeDetails[$detail.IdentityKey]=$detail}
    foreach($detail in @(Get-PCSessionSensorDetails $After)){$afterDetails[$detail.IdentityKey]=$detail}
    $keys=@(@($beforeDetails.Keys)+@($afterDetails.Keys)|Sort-Object -Unique)
    foreach($key in $keys){
        $left=$beforeDetails[$key];$right=$afterDetails[$key]
        $detail=if($left){$left}else{$right}
        $coverage='A '+$(if($left){$left.Coverage}else{'0 samples'})+' | B '+$(if($right){$right.Coverage}else{'0 samples'})
        foreach($stat in @('Average','Maximum')){
            $label=if($stat -eq 'Average'){'mean'}else{'peak'}
            $metric="$($detail.Device) / $($detail.Sensor) ($($detail.Type)) - $label"
            $rows.Add((New-PCComparisonRow $metric $left.$stat $right.$stat $detail.Unit ($null -ne $left -and $null -ne $right) $coverage))
        }
    }
    [pscustomobject]@{
        Schema=1;Kind='PCInsight.SessionComparison';Created=(Get-Date).ToString('o')
        Before=($Before|Select-Object Timestamp,Test,CPUName,Runtime,Workers,Renderer,DriverVersion,MemoryConfig,BufferMiB,WarmupSeconds,Plan,Seconds,Completed,StopReason)
        After=($After|Select-Object Timestamp,Test,CPUName,Runtime,Workers,Renderer,DriverVersion,MemoryConfig,BufferMiB,WarmupSeconds,Plan,Seconds,Completed,StopReason)
        ScoreComparable=$comparable;Reasons=$reasons;Notes=@($notes);Rows=@($rows.ToArray())
        Status=if($comparable){'Matching benchmark configuration. Review the conditions below.'}else{'Score change unavailable: '+($reasons -join ' ')}
    }
}
function Get-PCComparisonPowerContext($State) {
    if(-not $State -or $State.Issue -or -not @($State.Devices).Count){return 'unavailable'}
    (@($State.Devices|Sort-Object UUID|ForEach-Object {
        $watts=Get-PCComparisonNumber $_.Current
        if($_.UUID -and $null -ne $watts){'{0} = {1:N1} W' -f $_.UUID,$watts}else{'unavailable'}
    })) -join ', '
}
