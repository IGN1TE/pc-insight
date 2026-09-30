<p align="center"><img src="assets/branding/pc-insight-logo-v1.png" width="640" alt="PC Insight"></p>

[Download the latest release](https://github.com/IGN1TE/pc-insight/releases/latest) · [Development workflow](DEVELOPMENT.md)

Version 0.27.0 adds a CPU tuning readiness page, inventory-based guidance, an exportable report and access to the existing three-run CPU baseline. Direct CPU clock, voltage and package-power-limit writes remain unimplemented.

---
# PC Insight 0.24.0 - NVIDIA clock-offset preview

CPU/GPU sensor readings are now collected inside PC Insight through the bundled official LibreHardwareMonitorLib 0.9.6. You no longer need the Libre Hardware Monitor desktop app, Log Sensors, a CSV file or its remote web server.

## Start

Already installed? Open **Updates > Save feed and check**, then **Download update > Install and restart** once this version is published. Results and recovery records stay on your PC.

For a first installation, extract the complete ZIP and run **Install-PC-Insight.cmd**.
Use the desktop or Start menu shortcut, then **Scan PC**. Choose **Reopen as administrator**
when needed for direct CPU sensors or FPS capture. Sensor availability depends on hardware and drivers.
For the game overlay, open **Game overlay**, enable **Ctrl+Alt+O**, focus your game and
press the hotkey. Keep PC Insight open or minimized; pressing it again stops capture.

Your previous benchmark history and power-plan recovery record remain in `%LOCALAPPDATA%\PCInsight`. The old saved CSV path is ignored by the built-in connection.

## Hardware driver dependency

LibreHardwareMonitorLib 0.9.6 uses the PawnIO hardware-access driver for certain low-level readings. Bundling the library does not install PawnIO. If it is already installed, PC Insight uses it. If CPU temperatures are missing even when running as administrator, check the official Libre Hardware Monitor release information for its driver requirements:
https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/tag/v0.9.6

PC Insight does not download/install drivers, bypass driver blocks or disable Windows security features. A driver dependency does not require keeping another monitoring window open. Hardware support and Windows policy may still limit available sensors.

## What changed

- Embedded official sensor library and runtime dependencies; no separate Libre desktop executable is bundled or launched.
- Direct `Computer.Open`, hardware `Update` and sensor enumeration in the app's background worker. `Computer.Close` releases resources when the worker exits normally or through its cleanup path.
- CPU and GPU monitoring enabled. Motherboard, storage, fan and peripheral-controller monitoring remain disabled for this integration.
- Built-in sensor mode is the default; no log-selection setup.
- Separate administrator launcher uses Windows UAC only when the user chooses it. No automatic elevation or persistence.
- Bundled DLL hashes are checked before loading to detect accidental replacement or missing files. This integrity check is not a digital signature or a security trust guarantee.
- Existing actual-temperature filtering, missing-sensor stops, history repair and report export retained.

## Measurements and test limits

The original 15-second single-worker SHA-256 baseline remains on Benchmark. It does not use the monitored-test temperature guard. The monitored test is a 20-second parallel SHA-256 workload with up to 16 workers, reserving one logical processor where possible. It requires a valid CPU temperature and stops for a reported temperature at least 85 C, missing readings, a sensor error or a query longer than three seconds. An independent worker deadline bounds CPU load to approximately 20 seconds even if sensor collection stalls. Polling delays can still allow temperature overshoot.

85 C is this preview's conservative test cutoff, not a manufacturer limit or a guarantee of safety. Direct hardware updates are requested for each query, but sensor-level timestamps are not supplied by the library. Hardware-level freshness and accuracy cannot be guaranteed. Temperatures are Celsius; clocks are reported MHz, not necessarily effective clocks. The app excludes Distance to TjMax/headroom readings from absolute CPU temperature and stop decisions.

Tests measure their particular SHA-256 workload, not FPS or overall system health. Completion is not long-term stability certification. Compare the same test, CPU, runtime and worker count under equivalent conditions. GPU shader tests, RAM copy tests, guided NVIDIA power-limit reduction and the optional game FPS overlay are also available. Voltage tuning, AMD/Intel clock control, fan/BIOS/RAM writes, definitive thermal-throttling diagnosis and long-term stability certification are not implemented.

Older session summaries may still contain the pre-0.3.1 inflated temperature peaks. Raw samples remain available. New sessions use the corrected filter.

## Existing inventory and optimization

Windows CIM inventory reports CPU, RAM, GPU models/drivers, motherboard, BIOS, volumes and memory use. NVIDIA snapshot telemetry uses an already-installed nvidia-smi. Firmware RAM speed is not proof of XMP state, and disk space is not a disk-health test. Sensor monitoring in this release is scoped to CPU/GPU, although inventory still lists other components.

The Optimize tab switches only installed Windows power plans after approval. It records the original plan before applying, verifies the active plan and restores it on request. A plan change persists when the app closes. Use Restore previous plan to undo it. Recovery lives in `restore.json`; if the UI is unavailable, use the saved OriginalPlan GUID with `powercfg /setactive GUID`. Deleted plans cannot be recreated by this app.

## Privacy, packaging and licenses

No account, analytics, web server, scheduled task, startup service or network connection is needed. Reports and history stay local unless you export/share them. Review hardware identifiers and error text before sharing.

This preview is distributed as unsigned Windows PowerShell/WPF source. It requires Windows 10/11, Windows PowerShell 5.1 and .NET Framework 4.7.2 or later. Launchers use a process-only execution-policy override, not a persistent machine-policy change. Organization policy may block unsigned scripts; respect that policy.

The unmodified sensor DLL and dependencies come from the official 0.9.6 .NET Framework release. Licenses, dependency metadata, source links and the upstream source archive are in `vendor/LibreHardwareMonitor`. The included source scripts permit rebuilding/replacing the integration. No restriction on debugging modifications to the LGPL components is imposed. See `COMPONENTS.md` and included notices for third-party terms.

## Validation

Previous user reports confirmed inventory, single-worker tests, CSV-based monitored test and report export on an i7-13700K / RTX 5090 / ASUS Z690-A. Those reports do not validate the new direct integration.

Linux PowerShell tests cover direct-reader logic using mock hardware (update, missing values, headroom exclusion, cutoff, cleanup), the real bundled library's public API, bundled file hashes, CSV fallback regressions, history repair, mocked power-plan verification, and CPU-worker deadline/cancellation. XAML control wiring and PowerShell syntax are checked. Actual Windows hardware access, elevation and WPF rendering still need testing on your PC.

Read-only sensor tests:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-NativeSensors.ps1`

Additional regressions:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-LogSensors.ps1`
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Engine.ps1`

The engine suite briefly runs one CPU worker. Mock power-plan checks do not modify system settings.

## Results in preview 0.6.1

Open **Test results** after recording or running a monitored CPU test. The latest session shows sampled CPU temperature, package power, GPU core temperature, duration, throughput and sensor issues. It persists across restarts. Comparisons use the latest earlier successful run with matching test, CPU, runtime and worker count; power-plan differences are flagged. Short runs do not establish tuning headroom or causation. Exported JSON includes the readable latest summary. Old nested session history is flattened on load; historical CPU peaks in the summary are recalculated without Distance to TjMax sensors.

## Afterburn interface
Dark sidebar navigation, custom purple buttons, hardware cards and a measured CPU temperature chart. Scan populates hardware and memory cards. Recording updates temperature cards and the chart. Temperatures are last sampled values, not continuous background monitoring. The chart uses a fixed 0–125°C scale and actual query times; gaps represent missing readings. Saved session results and chart load on startup. Windows rendering still needs validation on the target PC.

Preview 0.6.1 adopts the selected Afterburn palette: near-black background, graphite cards, purple actions and cyan GPU accents.

Preview 0.6.2 fixes UTF-8 XAML decoding on Windows PowerShell 5.1 and sidebar title contrast.

## Preview 0.7 — Afterburn layout
Large processor panel, stacked graphics and memory cards, compact header, icon navigation and dark scrollbars. Record sensors directly from the dashboard. Latest session shows sampled CPU peak, SHA-256 throughput and comparison; View details opens the full report. Current temperature cards show their sample time. No continuous background collection is implied. Hardware artwork is a decorative vector chip, not a model-specific product photograph. The window remains resizable and the dashboard scrolls at smaller sizes.

## Preview 0.8 — Live monitoring and measured diagnostics
1. Scan PC to identify hardware.
2. Start live monitoring from the top toolbar, then use your normal game or application.
3. Overview plots CPU temperature and CPU/GPU/RAM utilization. GPU chart uses the first GPU core-load sensor; Insights identifies each GPU separately. No fabricated samples fill gaps.
4. Insights updates from the most recent 300 samples. Sustained-load candidates require at least 10 readings spanning 10 seconds, 80% coverage and 90% usage in at least 80% of available samples. These are app heuristics, not proof of a bottleneck. CPU temperature at 85 C triggers a review message, not a claim about a vendor limit.
5. Stop and save ends monitoring gracefully and saves the latest 300 samples. Older samples are discarded, so peaks refer to the retained window, not the entire monitoring run. Export includes measured diagnostics. Cancel or closing the app discards the current session.

Monitoring is read-only and starts no load or tuning. Other tests/settings actions are disabled until monitoring stops. The sensor library closes on normal stop. If sensor collection hangs for 30 seconds, the job is terminated and the app reports the failure. RAM load comes from Windows GlobalMemoryStatusEx; unavailable values stay missing. No automatic launch, background service, FPS, paging measurement or hardware writes were added. Windows hardware/long-session validation is still required.

## Preview 0.9 — Expanded benchmarks
Open Benchmark after Scan PC. Clicking one of the new labelled buttons starts that test directly; save other work beforehand.

- CPU 60 seconds: the same bounded SHA-256 workload, up to 16 workers, with a distinct test ID so 20-second and 60-second scores are not mixed. Requires CPU temperature and uses the existing 85 C / missing-reading / slow-query stop checks.
- RAM copy 20 seconds: two 128 MiB buffers (256 MiB total), repeated Buffer.BlockCopy, throughput in MiB/s of bytes copied once. Requires at least 768 MiB free physical memory and CPU monitoring. Initialization is outside the timed copy interval. A page-stride sample check follows; this is not a full memory integrity test. CPU, caches and runtime affect the score.
- GPU shader 20 seconds: native offscreen OpenGL, fixed 640x360 RGBA8 framebuffer and a 128-iteration GLSL 1.20 fragment workload, synchronous glFinish per draw. Results are draws/s for this synthetic workload, not game FPS or a vendor score. Renderer must match a Libre GPU core-temperature sensor by name. Stops at a sampled CPU or matched GPU core temperature of 85 C, missing GPU sensor or query over 3 seconds. Other GPU sensors are not substituted. Software/unsupported renderers or initialization failures return a clear error. No driver downloads or installations.

All tests support Cancel, bounded worker lifetimes and separate result identities. GPU comparisons require matching renderer/driver; RAM comparisons require matching reported memory configuration. A short completed test does not prove stability or tuning headroom. The default OpenGL adapter is selected by Windows/driver; manual GPU selection is not implemented. No WinSAT scores are used. GPU execution and Windows UI still need validation on the target hardware; Linux checks cover compilation, orchestration logic, actual RAM copy execution and cancellation.

Implementation references: Microsoft WGL context and glFinish documentation (https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-wglcreatecontext and https://learn.microsoft.com/en-us/windows/win32/opengl/glfinish), Khronos OpenGL 2.1 API/GLSL reference (https://registry.khronos.org/OpenGL-Refpages/gl2.1/xhtml/). These describe APIs, not validation of this app's benchmark.

## Preview 0.10 — Compatibility, baselines and GPU power limits
The new Tuning page provides a read-only compatibility query, a saved baseline and comparisons with subsequent matching tests. CPU/voltage/RAM controls are explicitly marked unimplemented; model names do not imply BIOS access. NVIDIA power minimum/default/current/maximum values come from the installed nvidia-smi executable. A reported range is only a capability candidate, not proof of write permission.

Workflow: Scan PC, run baseline tests, open Tuning, Detect compatibility, Save baseline, select a GPU and 90% or 80% preset, then Review and apply. The final review names the exact GPU, current limit and requested watts. The app re-queries immediately before writing, refuses stale values or invalid ranges, targets the GPU UUID explicitly, writes recovery and baseline files before mutation, and checks the setting afterward. Only reductions from the current cap are allowed; presets are calculated from the original cap. Restore first to move back up. Limits are watts, not voltage offsets or clock settings.

If an apply command fails or its reported value differs by more than 0.5 W, the app attempts to restore the immediately previous limit and retains the recovery record. Restore saved GPU limit targets the recorded UUID, checks the current range, verifies the original watts, then removes the record. Only one GPU can have an active recovery record at a time. No scheduled task or startup tuning is installed. Closing the app does not undo a change; external tools, driver resets or reboots may affect it. Unsupported devices or insufficient privileges produce errors. Run the admin launcher for vendor commands that require elevation.

Baselines contain the current inventory, driver-reported GPU limits, power plan and completed tests. Apply saves a baseline automatically before the first GPU change. Saving a replacement baseline while a GPU recovery record exists is blocked. Repeat the identical benchmark and use Compare with baseline. The report compares throughput and sampled temperature/power peaks when matching sessions exist, flags a >3% single-run regression as a candidate and reports power-plan differences. This threshold is a heuristic, not statistical significance. Sampled board-power peaks do not measure whole-system energy efficiency. Repeated equivalent runs are required before drawing conclusions.

Local recovery data: %LOCALAPPDATA%\PCInsight\gpu-power-restore.json. Baseline: tuning-baseline.json. Do not delete recovery data while a changed limit is active. Baselines save reported settings, not a BIOS image, full system restore point or unknown third-party clock offsets. GPU writes have been tested with a simulated vendor interface, including rejected writes and read-back mismatch recovery; actual Windows/NVIDIA write support still needs validation on the target machine.

Vendor reference: https://docs.nvidia.com/deploy/nvidia-smi/ — power limits must lie within the GPU-reported minimum/maximum and require sufficient privileges on supported devices. No unsupported driver workaround is attempted.

## Preview 0.11 — Three-run batches
Benchmark offers CPU × 3 (three 60-second runs), RAM × 3 and GPU × 3 (three 20-second runs). Each batch pauses 10 seconds between runs. CPU batches take roughly 3½ minutes plus setup/query overhead. Existing sensor guards apply independently to every run. Failures stop the batch; completed preceding runs and the failed diagnostic are saved on normal batch completion. Cancel or closing the app discards the whole current batch. No tuning is performed automatically.

The app records a batch ID and run index, queries GPU power limits and Windows power plan before/after each run, and excludes a run if those reported settings change during it. These checks cannot detect all BIOS settings or third-party changes. Repeated results groups by batch, test, hardware/runtime/driver/memory information, power plan and reported GPU limits. It shows count, median, minimum, maximum and spread. Incomplete or mixed-settings groups are labelled and not used as a complete batch comparison. Latest complete batches can be compared with a previous compatible batch, with reported settings differences and an observed-range overlap note. Three runs are not statistical significance or a stability certificate. Cooldown time does not guarantee equal starting temperatures.

Saved report exports include the repeated-test summary. Original per-run scores and sensor records remain available. Tests cover median calculation, partial batches, settings separation, range overlap, three-run orchestration and stopping after a failed run. Full batches still require Windows runtime validation.

## Preview 0.12 — GPU workload v2 and variability checks
GPU v2 uses a five-second unscored warm-up followed by 30 seconds of scored work. The framebuffer is 1280x720, the fragment shader runs 256 iterations, and eight draws are submitted before each glFinish. This increases GPU work relative to submission/synchronization overhead; whether it reduces variation on a given PC still requires measurement. The score remains wall-clock draws/s, not a GPU timer or game FPS. Warm-up is temperature-monitored and included in temperature/power peaks, but excluded from the throughput counter and elapsed scoring time. Cancellation and the existing sensor cutoffs apply during warm-up too.

The new test ID prevents comparisons to v1 results. Three GPU runs take roughly 2 minutes plus setup. Exported sessions include sampled throughput intervals for investigation. Repeated results flag >5% max–min spread/median as high variability; this is a product heuristic, not a statistical confidence bound. A comparison involving a high-variability batch is explicitly inconclusive. Original scores remain visible; no results are discarded as outliers and no hardware settings are changed by this update.

## Preview 0.13 — Tuning decisions use matched batches
The Tuning page now compares complete three-run groups saved in the baseline against complete groups measured afterward. Old single-run baseline reports remain in history but no longer produce a tuning verdict. Baseline save shows readiness; completing tests refreshes the comparison automatically.

Groups must have matching workload IDs, hardware/runtime/driver/configuration fields, power plan and reported GPU limits within each batch. Different GPU power limits between batches are shown explicitly. Comparisons report medians and spread; >5% variability, missing power-setting coverage, differing Windows plans or overlapping ranges are labelled inconclusive. Non-overlapping ranges are described as observed higher/lower throughput, not proof of causation or statistical significance.

Temperature/power comparisons require sensor records for all six runs and, for GPUs, match the named device. They report the median of sampled per-run peaks. Missing historical frames produce unavailable values. If all sampled power peaks are below both reported caps, the report says the samples do not demonstrate reaching either cap; it does not rule out unsampled transients. No efficiency or whole-system energy claim is made. No hardware is changed by this comparison.

## Preview 0.14 — Installer, profiles and session browser
Optional installation: extract the ZIP, close PC Insight, then double-click Install-PC-Insight.cmd. It installs only for the current Windows user under %LOCALAPPDATA%\Programs\PCInsight, creates desktop/Start menu shortcuts and a Windows Installed Apps entry. Updates are installed from a newly extracted folder using the same script. Installation stages files and verifies bundled-library hashes before replacing a recognized installation. It never overwrites an unrecognized destination folder or changes driver/security settings. This is an unsigned PowerShell installer, not a signed MSI/EXE or automatic updater. Do not run it using credentials for a different Windows account.

Normal and Administrator shortcuts are separate; the latter requests UAC when launched. Portable launchers remain available. The new purple app icon appears on shortcuts and the app window. Uninstall is available from Start menu or Windows Installed Apps. It refuses while PC Insight is open or settings recovery records exist. Restore saved power settings first. Uninstall removes application files and its shortcuts/registration; %LOCALAPPDATA%\PCInsight data remains.

Profiles: Save baseline in Tuning, then enter a name in Profiles and choose Save named profile. This stores an independent copy of the active comparison baseline. Duplicate names create separate entries; GUID filenames prevent a label from becoming a path. Load for comparison changes only the active baseline, never hardware settings. Switching baseline profiles is blocked while a GPU recovery record exists. Test results now lets you select among the latest ten retained sensor/test sessions; raw benchmark history remains capped at 100 saved entries.

Validation: profile save/load, duplicate names, invalid identities, script syntax and packaged-file integrity were checked. Windows shortcut creation, Installed Apps registration, installation/update/uninstall and WPF rendering require target-machine validation. Existing monitoring, benchmarks and tuning controls are unchanged.

## Version 0.15
- Header shows standard or administrator access. Access status is not a sensor compatibility guarantee.
- Reopen as administrator requests Windows UAC, then closes the idle original window. Cancelling UAC keeps the original window open. Finish monitoring or tests first.
- Saved results remain on disk; a new hardware scan is required after reopening. Unsaved scan state is not transferred.
- About provides app and saved-data folder buttons, and updated feature descriptions.
- Button hover visibility corrected.
- Update: close PC Insight, extract this ZIP into a separate folder, run Install-PC-Insight.cmd. Existing results and recovery records remain in the data folder.

- Updates tab defaults to https://github.com/IGN1TE/pc-insight/releases/latest/download/update.json and supports version checks, verified downloads, and Install and restart. An existing saved feed takes precedence over the default.
- Feed JSON: schema=1, appId=PCInsight.PerUser, version, downloadUrl, sha256, sizeBytes. Releases must contain PC-Insight/version.json and the complete app folder.
- Download limit 50 MiB, expanded limit 150 MiB. Updates are unsigned; only configure a release publisher you trust.
- No update check runs automatically. Update installation is disabled during tests/monitoring. Windows updater restart still requires validation.

## Version 0.16
Updates now shows optional plain-text releaseNotes from the manifest, download size,
and the last successful check in this session. Feeds without notes still work.
version.json drives runtime version display, report metadata, and update comparisons.
Windows UI and end-to-end installation still require validation.

## Version 0.17: selected-session export
Open Test results, choose a saved session, then Export readings CSV or Export this session.
CSV uses one row per sensor per retained sample, retaining device identifiers to keep
multiple GPUs distinct. Samples without sensors retain an empty sensor row and any issue.
Raw sensors include headroom readings under their original names; those are not actual temperatures.
Missing values are blank, not zero. UTF-8 BOM supports Excel; numeric values use a dot.
Formula-like text is prefixed with an apostrophe for spreadsheet safety.
JSON preserves the original session fields. No history from other sessions is exported.
Only retained samples exist to export (at most 300 for continuous monitoring).

## Version 0.18: saved-session sensor details
Test results shows a read-only sensor table beneath the session summary. Statistics use
finite readings in retained frames without a reported Issue. Coverage is valid sample
count divided by all retained frames. Duplicate readings for the same identity within
one frame count once. Average is a sample mean, not time-weighted. These are descriptive
statistics, not proof of throttling or a bottleneck. Headroom sensors retain explicit labels.

## Version 0.19: sensor history
In Test results, select a sensor row and scroll to its history graph. Points use recorded
timestamps with elapsed seconds from the first retained timestamp. Hover for values.
Missing/invalid readings and frames with issues break the line. Non-increasing or
invalid timestamps are excluded. A gap greater than three times the median interval
(minimum three seconds) also breaks the line. Single points and constant readings remain
visible; the displayed vertical scale is automatic. No missing readings are interpolated.

## Version 0.20: Optimize my PC
Scan PC, open Optimize my PC, then Check compatibility. The initial guided workflow
requires exactly one NVIDIA management device with readable limits and a valid
90% reduction from its current ceiling. Existing GPU recovery records must be restored first.

Run baseline performs three GPU v2 tests (5-second warm-up + 30-second measurement
each, 10-second cooldowns). Baseline variability above 5% blocks applying. Review,
apply and retest explicitly confirms the actual GPU UUID and wattages, saves the
baseline/original limit, verifies the write, and automatically runs three more tests.
Both batches must match device, driver, power plan, runtime and test configuration.
The verdict displays descriptive medians, spread, power/temperature context and a
recommendation. Keep is always a deliberate choice; no auto-keep or startup reapply.

Cancel during a retest stops the worker and attempts restore. Failed tests do the same.
Closing at the decision stage offers restore or returns you to Keep/Restore. Closing
after Keep retains the setting and recovery record. A process/PC crash cannot guarantee
restoration; next launch shows recovery, with NO automatic hardware write. Restore
remains available, and failed recovery does not delete the original record.
The data file guided-optimization.json preserves this workflow separately from the
ten-session browser limit. Export guided report includes its before/after records.
No CPU overclock, GPU clock offset, voltage, fan or BIOS changes are added.

### Windows acceptance checks for this milestone
- Run tests/Test-GuidedOptimize.ps1 (simulated hardware), Test-SessionChart.ps1 and
  Test-Interface.ps1 under Windows PowerShell 5.1. These tests make no hardware changes.
- Confirm workflow controls and guided report display at your normal Windows scaling.
- On supported hardware: baseline -> reviewed apply -> retest -> Restore; verify the
  original limit independently. Then test a deliberate cancel during a retest.
- Exercise Keep only if you choose; verify Restore remains available after reopening.
- Startup interrupted-state recovery and actual restoration failures need hardware
  validation. Do not deliberately terminate during a write to test this.
- Validate v0.17 -> v0.20 update/install and existing history/profile preservation.


## Version 0.21: game overlay and clear outcomes

Game overlay is off by default. Enable its Ctrl+Alt+O hotkey while PC Insight is open,
then toggle a small top-left, click-through panel in your windowed or borderless game.
It follows the foreground application and its monitor. Exclusive fullscreen can hide it.
The hotkey is registered through Windows; a conflict reports an error without taking
over another app's shortcut. Show overlay is also available from the page.

CPU is the highest valid CPU temperature supplied by the existing sensor reader.
GPU is core temperature; multiple GPUs show the hottest core with a GPU max label.
Temperatures are sampled about once a second and cleared if older than five seconds.
Hardware sensor timestamps are unavailable; this freshness check refers to the query.
Unavailable temperatures remain --. Administrator access or the existing sensor
hardware driver may be required.

The bundled, hash-verified PresentMon 2.6.0 standalone console provides FPS through
ETW. Only the foreground process is targeted. The rate uses successive application
presentation timestamps over up to two seconds from the busiest observed swap chain;
independent swap chains are not added together. It is not displayed/generated FPS.
At least five frames are required. Readings clear after 2.5 seconds without new data.
Protected or unsupported games may return no FPS. Reopen as administrator if capture
reports access denied. No additional service, injected game DLL or FPS CSV is installed.

Hiding the overlay stops its capture and sensor worker. It pauses when an app task
starts, including tests and updates; use the hotkey to resume after the task finishes.
Closing the app unregisters its hotkey and stops its private ETW session. Capture uses
unique session names and never stops other tools' sessions. Five-minute capture
intervals renew while visible; a brief FPS gap can occur on renewal. This bounds the
child capture after an abrupt app crash. Overlay values are not added to test history.

Guided results now separate the saved action status from the measured recommendation.
Restore/Keep buttons show exact wattages. Restored and kept outcomes explicitly refer
to their saved read-back, not a fresh hardware query. Pending recovery overrides an
old success banner. Results show baseline/retest medians and percent change, with
full details expandable. Sidebar labels wrap and the footer reads version.json.

Windows acceptance remains required for the new overlay: global hotkey, focus/click
pass-through, real game FPS, temperature access, high-DPI/multi-monitor positioning,
normal close/reopen and update installation. Run tests/Test-Interface.ps1 with -STA
for hidden-window binding/native-style checks, and tests/Test-GameOverlay.ps1 for
calculation/dependency checks. These scripts make no hardware setting changes.


### App-only launch
Desktop/Start menu shortcuts, normal launchers, administrator launches and update
restarts now pass PowerShell's Hidden window style. PowerShell still hosts the app;
the console stays hidden during normal use. The installer refreshes existing
shortcuts. UAC prompts remain visible when administrator access is requested.
Batch files can briefly show their own command window while starting; use the
installed shortcut for normal use. Start-PC-Insight-Debug.cmd keeps the console
visible for troubleshooting. Early launcher errors produce a dialog and, when the
data folder is writable, %LOCALAPPDATA%\PCInsight\startup-error.log.


## Version 0.21.1: overlay hotkey crash fix
The v0.21.0 Ctrl+Alt+O callback tried to assign a Value property to the Boolean
handled argument supplied by WPF. That caused a runtime exception while the main
window's dialog loop was running. The hotkey now uses a managed C# method with the
correct ref bool signature; PowerShell receives only the zero-argument toggle callback.
The existing key, panel, FPS capture and hidden launch behavior are preserved.
Regression checks exercise repeated hotkey calls and the handled flag through the
same delegate signature. Test-Interface also invokes the real WPF HwndSourceHook
on Windows. A live hotkey/show/hide check on Windows remains required.


## Version 0.21.2: FPS compatibility and capture details
FPS capture now retains PresentMon's normal GPU/display event tracking instead of
the reduced no_track_gpu/no_track_display mode. Input timing remains disabled.
This is a compatibility change; it is not a confirmed fix for every game.
The v0.21.1 hotkey fix and existing temperature readings are retained.

The overlay stops saying waiting indefinitely: after ten seconds without usable
frames it shows no FPS data, with a more specific explanation on Game overlay.
The last meaningful capture result stays visible after Alt-Tab or hiding the overlay.
Export FPS details saves a small JSON report for troubleshooting. It includes app
version, elevation status, the targeted process name/ID, capture mode/duration/exit
code, output/header/accepted/rejected/wrong-process counts, the first output line,
CSV header and up to eight bounded stderr lines. No full process list is included;
no report is uploaded or written automatically. The data is a snapshot, not a
running process object. The file may contain the game name and diagnostic text;
review it before sharing.

The prior waiting message alone could not distinguish missing game events from a
CSV/parser problem. The new details provide that evidence. Tests verify the complete
PresentMon v1 CSV layout, frame calculations, message distinctions and report
snapshots. A simulated child-process pipe check verifies asynchronous stdout/stderr
reading and cleanup. Actual Windows/Skate capture still requires local verification.

## Version 0.22: compare saved sessions
In **Test results**, the top selector chooses session B. Under **Compare saved sessions**,
choose reference session A. The table shows benchmark throughput, recorded duration,
and each sensor's mean and peak side by side. Change is B minus A; there is no automatic
better/worse verdict. Both selectors use the existing ten retained sessions.

Score changes require two different, successful runs of a supported matching test version,
CPU, runtime and worker count. GPU tests also require matching renderer, driver and warm-up;
RAM tests require matching memory configuration and buffer size. Missing metadata, invalid
scores, or durations differing by over 10% (with a two-second tolerance) block score changes.
Power-plan differences and recorded GPU limits are shown as context; this does not prove
that a setting caused a performance change. Repeat equivalent tests to assess variation.

Sensor rows match full saved sensor identities, keeping separate GPUs distinct. They show
all sensors present on either side; missing values remain unavailable. Only retained samples
without sensor issues contribute, with duplicate identities counted once per frame. Means
are sample averages, not time-weighted. Different activities and coverage affect readings.
Temperature headroom is labeled separately. No overlay/game FPS history is implied.

**Export comparison** saves the displayed comparison, session metadata, compatibility
reasons, and sample coverage as JSON. It does not export unrelated sessions or change settings.
Saved comparison export remains available during active tasks/updates. Older sessions can still be inspected even
when they lack metadata required for a score comparison.

Windows PowerShell 5.1 comparison and hidden WPF integration tests pass. Interface rendering
was inspected at 1320 and 1000 pixels with sample data. The interface test now handles both
LF and CRLF source files. Existing live-game behavior was reported working by the user before
this feature; no new game capture or hardware tuning test was performed for this release.
## Version 0.22.1: comparison export availability
Comparison export is a read-only save of existing results. It now remains enabled while
monitoring, a benchmark, or an update check is active. The exact displayed comparison is
copied before the Save dialog opens, so a task completing in the background cannot replace
the selected report. Cancelling the dialog writes nothing.

Reference A excludes the run selected as B. Selecting another B preserves a valid reference
or chooses another available run. Missing sessions and loading errors are explained beside
the disabled export button, which also has a tooltip.

Windows tests exercise the real selection handlers, busy-state changes and export button,
with a stubbed file picker and real JSON saving. Existing saved sessions were read only for
diagnosis; no saved results or hardware settings were changed.
## Version 0.22.2: project branding

The new purple/cyan PC Insight logo appears in the sidebar and About page. About and the sidebar show the installed version. Desktop, Start menu, Installed Apps and the app window use the matching icon, with nine native sizes from 16 to 256 pixels. Installation uses a versioned icon filename to avoid stale Windows icon-cache entries. Branding loads from the app folder even when launched from another working directory.

The v0.22.1 comparison export fix is retained. This release changes presentation and shortcut branding; it does not add hardware actions or change saved sessions. WPF integration, comparison export, updater and extracted-package checks were run on Windows. UI layouts were inspected at 1320x920 and 1000x720, with additional 150% and 200% raster rendering checks.
## Readable comparison reports

In Test results, select session B and a reference session A, then choose **Save
readable report**. The standalone HTML file opens in a browser without an internet
connection. Use the browser's Print command to print or save as PDF. The report
includes the displayed measurements, sample coverage, both sessions' recorded
configuration and comparison limits. It keeps missing values and blocked score
comparisons explicit. **Export comparison JSON** remains available for data analysis.

The report is frozen before the Save dialog opens, even if monitoring updates the
session selectors. Cancelling saves nothing. Reports may contain hardware details
and recorded settings; sharing is up to you. Nothing is uploaded automatically.

## NVIDIA GPU overclocking preview (0.24.0)

Tuning now includes **Detect clock support**, manual graphics/core and memory MHz
offsets, **Review and apply offsets**, and **Restore saved clock offsets**. This
first implementation uses NVIDIA's documented NVML clock-offset API for P0. It
requires a 64-bit Windows process and a driver exposing those functions (introduced
in R555). Actual availability is determined by read calls, not a GPU-name whitelist.
RTX 5090 write support and behavior have NOT been verified on hardware here. An
unsupported driver/device stays disabled; a read success does not guarantee writes.

Detection is read-only. Applying requires administrator access, a current readable
GPU temperature below the 85 C preview cutoff, whole-MHz values within the reported
ranges, and explicit review of the GPU identity and requested values. The cutoff
and driver ranges are not stability guarantees. P0 is the highest performance
state; this preview does not claim control of every P-state. Memory values are raw
NVML MHz offsets, not effective DDR data rates or another tool's slider units.

Close games and other tuning tools and save work before a change. Unstable offsets
can cause artifacts, driver resets, crashes and lost work. This is manual tuning,
not automatic stability testing or an OC scanner. No voltage, fan, BIOS, driver
installation, power-limit increase or startup profile is added.

The original offsets (which may already be nonzero) are flushed to
`%LOCALAPPDATA%\PCInsight\gpu-clock-restore.json` before writing. Both offsets are
read back after apply. A rejected write or mismatch attempts both rollback domains
independently, and retains the recovery record. Later edits never replace the
original values. Restore is explicit, available after relaunch, and requires
readback before the recovery file is removed. Temperature checks do not block
restoration. A driver/system crash can prevent in-process recovery; no watchdog or
automatic restoration after app exit is claimed. Do not delete a pending recovery
record to bypass a blocked apply.

Benchmark snapshots record reported P0 offsets when available. Repeated runs with
different reported offsets are separated, and session comparison includes this
context. Older sessions show it as unavailable. These snapshots cannot detect every
external tuning change. Guided power-limit optimization requires restoring the
saved manual clock changes first. Manual benchmarks remain available.

Validation here covers mocked writes/failures/recovery, NVML structure layout,
clock-context grouping, comparison and updater regressions. Windows PowerShell 5.1,
WPF interaction, native detection and reviewed hardware writes remain validation
requirements. `tests/Test-GpuOverclock.ps1` is mock-only;
`tests/Test-GpuOverclockUI.ps1` requires Windows WPF and also mocks every GPU write.

Implementation references:
- https://docs.nvidia.com/deploy/nvml-api/change-log.html (R555 clock-offset functions)
- https://docs.nvidia.com/deploy/nvml-api/latest/api/group__nvmlDeviceCommands.html
- https://github.com/NVIDIA/go-nvml/blob/main/pkg/nvml/nvml.h (public ABI)
No NVIDIA DLL is redistributed; the installed library is loaded from Windows
System32 or the vendor NVSMI directory, never from the app working directory.

## Guided core trial (0.25.0 candidate)

On Tuning, scan the PC and detect clock support, then record three GPU shader baseline runs. Review the proposed +15 MHz core offset before applying it and running three retests. The memory offset is unchanged. The result compares median shader draws/second, run variation and available sampled GPU Core temperature peaks; it does not measure game FPS or certify stability. Choose Keep or Restore explicitly. This first workflow requires exactly one NVIDIA GPU and administrator access for writes; it does not search for a maximum overclock or alter voltage.

Existing saved clock or power changes must be restored before starting. Driver, GPU identity, power plan, power limit and recorded clock offsets must remain compatible. Cancellation or a failed retest attempts to restore the saved original offsets. A system crash can prevent that attempt; relaunch marks an unfinished applied trial as requiring recovery and performs no automatic GPU writes. Keep retains the original-offset journal for restoration and does not configure startup reapplication. Trial progress is stored in guided-core-trial.json beside the app's existing per-user data; the existing clock recovery journal remains authoritative for original offsets.

Validation scope: the user previously observed successful +15 MHz core apply/readback and reset on one RTX 5090 with driver 616.92 using 0.24.1. That does not establish positive memory-offset compatibility or stability. The new guided sequence has simulated workflow/handler coverage on Linux PowerShell; actual Windows WPF, worker integration, closing/relaunch recovery and physical GPU trials must be checked before publishing this candidate.

## Reference dashboard design

The Overview now follows the user-supplied dark navy/purple concept with a slim sidebar, large processor card, stacked graphics/memory cards and a combined latest-session summary and temperature chart. Hardware art is generic vector decoration, not a product identification or sensor reading. Model names, readings and charts retain the existing live/saved-data bindings; unavailable readings remain unavailable. Existing pages and Windows title-bar controls remain accessible. The utilization chart is under its own expander.

Validate on Windows before publishing: run tests/Test-Interface.ps1, inspect 1320x920 and 1000x720 sizes plus 125–150% display scaling, long device names and missing readings, sidebar scrolling, keyboard focus, all Overview buttons, populated session values/charts, and tuning recovery controls. Linux validation only confirms XML structure, resource references and unchanged named controls; it does not establish WPF rendering or pixel fidelity.

## GPU endurance (0.26.0)

After a hardware scan, open **Benchmark** and choose **GPU · 5 minutes** or **GPU · 10 minutes**. These run the existing offscreen shader workload continuously, with a five-second warm-up and live progress. Save work and close games first. **Stop and save result** retains the partial observation and stop reason. Open **Test results** for elapsed time, matched GPU peak temperature and limits. Endurance sessions do not create comparable benchmark scores.

The test uses current clock settings and makes no tuning changes. It does not automatically restore offsets; use **Tuning → Restore original** for that. A successful interval is not proof of stability: there is no pixel-correctness, VRAM integrity, WHEA, driver-reset-log or game validation. Missing/invalid/slow sensors, sampled 85 C CPU or GPU temperatures, API errors and stalled progress stop the test. Native workload checks a six-second sensor heartbeat between rendering batches; a blocked graphics driver can delay cancellation. Interrupted tests are marked at the next app startup, never claimed as completed.

Validation: mocked 300/600-second orchestration, partial cancellation, temperature/sensor/native failures, cleanup and native heartbeat checks passed under PowerShell 7 on Linux. Existing guided-clock, repeatability, result/comparison and updater checks passed. Windows PowerShell 5.1, WPF layout, physical GPU duration, driver cancellation and updater installation still require target-machine validation.

## CPU tuning readiness (0.27.0)

Open **CPU tuning → Scan CPU and motherboard**. The report shows the inventory timestamp, processor, board model and BIOS version reported by Windows. Recognized Intel unlocked-style model names are candidates for checking vendor requirements only. AMD, mobile/unrecognized models and multiple processors never imply writable controls. No board chipset, firmware locks, tuning ranges or installed vendor tools are probed or inferred.

**Run CPU baseline · 3 tests** uses the existing three monitored 60-second SHA-256 runs and cooldowns. Save work first. The workload checks CPU temperatures and stops at the preview cutoff; it is not a stability certificate. Cancel discards the batch, as on Benchmark. Read **Repeated results** for medians and variability and **Test results** for recorded temperatures. **Export readiness report** saves this report as JSON without serial numbers, account details or unrelated sessions.

Direct CPU overclocking requires a validated vendor interface with capability detection, original-setting capture, write/readback and recovery. That interface is not integrated in this release. Windows power-plan selection remains a separate existing feature on Optimize and is not represented as CPU overclocking.

References reviewed 2026-09-30:
- Intel XTU hardware/firmware requirements: https://www.intel.com/content/www/us/en/support/articles/000006636/processors/processor-utilities-and-programs.html
- Intel CPU and XTU-version support: https://www.intel.com/content/www/us/en/support/articles/000057552/processors/intel-core-processors.html
- AMD Ryzen Master: https://www.amd.com/en/products/software/ryzen-master.html

Validation: read-only classification, missing/multiple/vendor cases, real UI-handler dispatch/locking/export with mocked controls, existing endurance and guided-clock handlers, repeated tests, updater, PowerShell parsing and XAML wiring checked on Linux. Actual Windows WPF layout and CPU-page interaction remain to be validated.

## CPU page usability (0.27.1)

Control descriptions use explicit wrapping in a vertical layout to avoid the clipping seen on Windows in 0.27.0. **Cancel CPU batch** is now available beside Run CPU baseline and only acts on a running three-test CPU batch. It uses the existing cancellation behavior, which discards that batch. The screenshot confirmed inventory display for an i7-13700K, ASUS ROG STRIX Z690-A GAMING WIFI D4 and BIOS 4505; CPU write support is still not established.
