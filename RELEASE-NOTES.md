# v0.28.0 - Recorded GPU sensor graphs (development preview)

- Retains bounded GPU temperature, clock, power and load samples from the existing workload, with full sensor identities and explicit missing readings.
- Adds run/sensor selectors, per-run graphs, coverage and min/mean/max to saved trials. Graph browsing stays available during an active trial.
- Separates equally named sensors and GPUs; labels temperature headroom. Invalid/duplicate readings, query errors, slow queries and timestamp gaps do not become continuous lines.
- Preserves telemetry through checkpoints, history and JSON exports. Older reports explicitly show unavailable timelines and clear stale graphs.
- Adds pure-data and actual Windows WPF regression coverage. No new hardware queries or clock writes are introduced by telemetry capture or browsing.

This source preview remains pending target-PC acceptance and does not publish an updater release.

# v0.27.0 - Saved GPU experiments (development preview)

- Archives each finished clock trial and preserves the previous checkpoint before it can be overwritten. Keeps stopped/interrupted results and isolates corrupt archives without deleting them.
- Adds a saved-trial browser, source report export, and A/B comparison export with both experiments included.
- Recalculates medians from individual runs; requires matching GPU, driver, original offsets, power settings and workloads. Flags baseline drift, noise, temperature differences and overlapping ranges as inconclusive.
- Loads requested offsets into the controls after fresh device/range checks. Loading never applies settings or starts a trial and is blocked during active tasks or pending recovery.
- Keeps history browsing/export available during a trial. Freezes exports before the file dialog so a background completion cannot change the chosen report.
- Preserves v0.25/v0.26 reports. History and comparison actions are read-only with respect to hardware.

Target-PC clock writes, real thermal response and stability still need acceptance. This source preview does not publish an updater release.

# v0.26.0 - Repeated GPU clock trials (development preview)

- Makes three baseline runs and three retests the default, with a quick one-pair option.
- Blocks clock application when baseline spread exceeds 5% of the median.
- Reports median, range, spread and every run's start/peak GPU temperature. Noisy, overlapping or temperature-mismatched groups are marked inconclusive; quick pairs cannot establish repeatability.
- Requires consistent GPU power limit and Windows power plan at run boundaries and before applying. Lost or changed settings stop the comparison and trigger clock restoration after an apply.
- Checkpoints individual results after each completed run; partial and excluded results remain available. Supports legacy v0.25.0 report display.
- Extends simulated recovery, report and Windows UI coverage for repeated runs, late cancellation, power changes and run-quality gates.

Three runs are descriptive, not statistical significance, a stability certificate or a game FPS prediction. The 5% spread and 5 C starting-temperature cutoffs are comparison heuristics. Real GPU writes and thermal behavior remain unverified. This branch does not publish an updater release.

# v0.25.0 - Measured GPU overclock trials (development preview)

- Adds a reviewed baseline/apply/retest/restore workflow for NVIDIA P0 core and memory offsets.
- Runs the same 5-second warm-up and 30-second shader workload before and after the change, with a 10-second cooldown. Reports throughput, sampled peak temperature and the measured change.
- Automatically attempts to restore original offsets after completion, cancellation or failure, and verifies both domains. Unresolved recovery remains on disk and blocks another trial.
- Checks GPU identity, clock offsets, driver and temperature during the trial. Requires one NVIDIA GPU and a matching OpenGL renderer/temperature sensor.
- Runs in a background worker. Stop requests are cooperative; closing the window requests cancellation and keeps it open while restoration finishes.
- Saves the last trial report locally, restores its display after relaunch and supports JSON export. Saved results are clearly distinguished from a current hardware check.
- Adds automated Windows PowerShell 5.1/WPF regression validation on GitHub.

A single short comparison is not stability certification, artifact detection, VRAM testing or a game FPS prediction. Physical clock writes and performance still require validation on the target GPU. App termination, driver hangs or power loss can prevent restoration; use the saved recovery controls on the next launch. This source preview does not update the public release feed.

# v0.24.1 - Windows GPU controls preview

- Integrated the v0.24.0 NVIDIA clock-offset controls and readable comparison reports.
- Recheck current GPU temperature immediately before applying offsets; reject invalid temperature values.
- Block uninstall while a clock-recovery record remains, including a corrupt record.
- Windows PowerShell 5.1 mock apply/restore, WPF button, comparison/export and updater checks passed.
- A read-only Windows probe successfully read offsets on an RTX 5090. Physical clock writes and stability remain unverified.
# v0.24.0 - NVIDIA clock-offset preview

- Adds read-only clock detection and reviewed manual P0 core/memory offsets on supported NVIDIA drivers.
- Saves original offsets before writes, reads back both domains and attempts recovery after partial failures.
- Restores saved offsets after relaunch, retaining recovery records until readback succeeds.
- Records available clock offsets with benchmarks and displays them in session comparisons.
- Retains the v0.23.0 readable comparison report feature and the working overlay.
- GPU/driver write compatibility and Windows UI validation remain pending; this is not a validated RTX 5090 overclocking release.

# v0.23.0 - Readable comparison reports

- Save a standalone HTML report from Test results, alongside JSON export.
- Includes benchmark and sensor changes, sample coverage, session details and comparison limits.
- Opens offline in a browser; use Print to print or save as PDF.
- Retains missing readings and blocked score comparisons exactly as displayed.
- Freezes the report before Save opens; cancellation writes nothing.

# v0.22.2 - PC Insight branding

- Added the purple/cyan PC Insight logo to the sidebar and About page.
- Updated the app window and installed shortcuts with the matching multi-size Windows icon.
- Version-specific shell icon filenames prevent reusing a cached old icon path.
- About and sidebar version labels use the installed release metadata.
- Retained v0.22.1's comparison export and session-selection fixes.
# PC Insight 0.22.1 - comparison export fix

- Export a loaded saved-session comparison while monitoring, tests or update checks run.
- Freeze the displayed report before opening Save, so background refresh cannot change it.
- Exclude selected session B from reference A and automatically retain a distinct reference.
- Explain unavailable exports beside the button and in its tooltip.

Full Windows selection/export workflow, comparison, WPF and updater tests passed.
# PC Insight 0.22.0 - saved-session comparison

- Select a reference session A and compare it with selected session B in Test results.
- View benchmark throughput, duration, and sensor mean/peak changes with sample coverage.
- Block misleading score comparisons across incompatible, incomplete or invalid runs.
- Keep devices separate and preserve unavailable readings; show power-plan/limit context.
- Export the comparison and its limitations as JSON.
- Fix LF/CRLF handling in the Windows interface validation harness.

Comparison, sensor statistics, updater and WPF checks passed on Windows PowerShell 5.1.
One pair of benchmark runs is descriptive evidence, not proof of an improvement or game FPS.
PC Insight 0.21.2 - FPS capture compatibility and troubleshooting
- Uses normal GPU/display event tracking for broader FPS capture compatibility.
- Missing FPS now gets a specific capture status instead of waiting indefinitely.
- The last capture result remains available after Alt-Tab or hiding the overlay.
- New Export FPS details button saves a small local report when readings are missing.
- Keeps the working temperature overlay, Ctrl+Alt+O crash fix and hidden PowerShell launches.
- Frame parsing and simulated streaming checks pass. This change still needs a Windows game test; Skate compatibility is not yet confirmed.
