# PC Insight 0.29.0 — testing tonight

This release adds result review and diagnostic evidence. Automated Windows PowerShell 5.1/WPF and package checks passed; target-PC appearance, real event-log access and installation still need your acceptance.

1. Restore any saved CPU package limits in your current installation before installing; the installer blocks an outstanding CPU recovery record. Close PC Insight and extract the entire ZIP, then run Install-PC-Insight.cmd.
2. Confirm About shows 0.29.0. Scan PC. Open Benchmark and find Saved GPU endurance results. Older endurance sessions should appear with event evidence marked "not collected".
3. Run GPU 5 minutes at your existing settings. Check Stop is enabled. Stop after around 20 seconds and confirm a stopped result is saved with measured duration and reason.
4. Select that result under Saved GPU endurance results and export it. Cancel the save dialog once to check cancellation, then export JSON. Open Test results to inspect the same session and its sensors.
5. Run a full 5-minute test. Review the Windows event section. "Unavailable" is a collection problem; "No matching events" is not a stability guarantee. If events are shown, send the exported JSON. Do not increase offsets based solely on completion.
6. Reopen the app and confirm both results remain selectable. Refresh while an older result is selected; your selection should stay in place. Only the ten latest sensor sessions across all test types are retained, so export anything you want to keep.
7. Open CPU tuning and confirm existing before/after results, settings detection and restore controls still appear normally. Check the in-game overlay once.

Windows developers: run `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/Test-Release.ps1` from the source checkout. The distributable excludes developer tests and tools.
