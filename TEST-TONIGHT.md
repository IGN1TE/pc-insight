# PC Insight 0.32.0 — automatic scan acceptance

1. Update through the app and confirm About shows 0.32.0. Restore any pending saved tuning changes. Reopen as administrator, Scan PC, then Detect clock support on Tuning. Save work and close games/other tuning utilities.
2. Select **Automatic scan baseline**. Three baseline runs should finish without changing clocks. Cancel the next review once and confirm no clocks changed.
3. Select **2. Review and retest**, read the three proposed offsets and confirm. It should test +15, +30 and +45 MHz above the starting core offset automatically (three runs each). The memory offset must stay unchanged. Cancel remains available.
4. When finished, confirm the app says starting offsets restored. Detect clock support and check those exact original values. Read the per-step measurements. A no-recommendation result is valid; do not force a higher offset.
5. If there is a recommendation, choose **Review recommended offset** and cancel once. If you then choose to apply it, verify readback and use Restore to return to your starting settings. Later game/endurance testing is separate; a completed scan does not prove stability.
6. In a fresh scan, Cancel during a retest. Check the original offsets are restored. Do not deliberately crash or kill the app during a hardware write. If recovery fails, retain the recovery record and use Restore original.

These physical checks are pending; automated tests use simulated GPU writes.

# PC Insight 0.31.0 — report check

Select a saved result under Test results and choose **Save readable result**. Cancel once to confirm nothing is saved, then save the HTML and open it in your browser. Check its note, session identity, sensor coverage and event evidence against the app. Try browser Print → Save as PDF if you want a document to share. Test a stopped endurance result and an older result with no event evidence. No second result is needed.

# PC Insight 0.30.0 — saved-results checks

1. Open Test results. Filter CPU/GPU/RAM/Monitoring, type part of a date or hardware name, then Clear filters.
2. Select an important result, type a note and choose Pin result. Close and reopen; confirm the pin and note remain. Use Pinned only to find it.
3. Choose a result and comparison reference, then change result filters; the reference list should still include other saved sessions.
4. Export JSON and CSV during a sensor recording or test. Cancel Save once, then save a file. Confirm the export belongs to the chosen saved result.
5. Check the page at your usual Windows scaling and minimum window size. Send a screenshot if anything clips.

The app keeps 30 recent unpinned sensor sessions plus up to 20 pins. Pins stay on this PC; export a separate backup for important runs. Unpinning allows future rolling removal. Results lost under earlier retention limits cannot be recovered by this update.

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
