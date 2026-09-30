function New-CpuContextFixture {
    [pscustomobject]@{CPU='Mock CPU';Manufacturer='Mock vendor';Cores=8;Threads=16;Board='Mock board';BIOS='1.0';OS='10.0.26100';Memory='DIMM0:17179869184:3200';Plan='381b4222-f694-41f0-9685-ff5bb260df2e';Runtime=[Environment]::Version.ToString()}
}
function New-CpuRunFixture([int]$Index=1,[double]$Score=100) {
    $frames=@(0..60|ForEach-Object{[pscustomobject]@{Timestamp=([datetimeoffset]'2026-01-01T00:00:00Z').AddSeconds($_).ToString('o');CPUCelsius=50;QuerySeconds=0.1;Issue=$null}})
    [pscustomobject]@{RunIndex=$Index;Test='SHA256-1MiB-parallel-60s-v1';Seconds=60;MiBPerSecond=$Score;Workers=8;Runtime=[Environment]::Version.ToString();Completed=$true;StopReason=$null;PeakCPU=50;StartCPU=50;TemperatureSamples=61;Frames=$frames;ContextBefore=(New-CpuContextFixture);ContextAfter=(New-CpuContextFixture)}
}
function New-CpuBaselineFixture {
    $r=New-PCCpuTrial 'Baseline' 'Original saved BIOS profile' $null
    $r.BeforeRuns=@(1..3|ForEach-Object{New-CpuRunFixture $_ (99+$_)})
    $r.State='Ready';$r.Message='Fixture baseline';$r
}
