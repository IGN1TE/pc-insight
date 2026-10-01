# 0.28.1 - CPU measurement comparisons

- CPU tuning now displays saved three-run batches with selectable reference A and result B, median/range/spread, peak temperature and coverage, and recorded PL1/PL2 settings.
- Incomplete or mismatched runs, changed/missing boundary settings, and missing CPU identity/BIOS/power metadata block percentage comparisons. High variation and overlapping ranges are labelled.
- JSON export preserves the selected comparison while the save dialog is open. Saved selections survive refresh; cancelled tests retain earlier history.
- Progress records the user-confirmed CPU power detection, 248/253 W apply/readback, restoration to 253/253 W, and same-boot close/reopen recovery.
- No multiplier/voltage controls are added. The signed module lacks direct turbo-ratio writes; the inspected mailbox implementation only declares older CPU-generation support.

Validation: saved-data and actual-handler mock tests, existing CPU measurement/power/UI and updater regressions, script parsing and XAML control bindings on Linux. Windows WPF rendering and this update's installation remain to be checked on the target PC.

# v0.28.0 — CPU power-limit preview

- Adds real Intel package-power detection and reviewed PL1/PL2 reductions on the initial i7-13700K / Raptor Lake B7 target, using an already installed PawnIO driver and an official signed module.
- Saves original settings before writing, checks for conflicts, reads back changes, attempts rollback on failure and offers explicit restoration after reopening on the same boot.
- Restricts the form to whole watts, 25–253 W, PL1 no greater than PL2, and neither limit above its current value. Preserves timing, enables, clamping and protection bits. CPU ratios and voltage are still unavailable.
- Includes CPU power context in benchmark measurements and comparisons, and excludes scores when the start/end settings differ.
- Blocks installation/uninstallation while a CPU recovery record remains; tasks, updates and other tuning controls lock during CPU changes.

Validation: native C# 5 compilation, protocol/bit guards, transaction and UI failure paths, installer recovery, benchmark metadata, existing GPU workflows, updater, PowerShell parsing and XAML binding checks passed on Linux. This preview still needs physical Windows detection, apply, readback and restoration acceptance. Register readback is not proof of the effective hardware power cap or of stability. Firmware may impose other limits. No driver is installed and no CPU changes run automatically at startup.

# v0.27.1 — CPU page readability and cancellation

Fixes clipped CPU control descriptions with explicit wrapping and stacked rows. Adds Cancel CPU batch directly to the CPU page, enabled only during the existing three-run CPU workload. Cancellation retains the existing batch-discard behavior. CPU overclocking/voltage/power-limit writes remain unavailable.

The user screenshot confirmed that 0.27.0 correctly displayed the i7-13700K, ASUS ROG STRIX Z690-A GAMING WIFI D4 and BIOS 4505 inventory. Automated handler and updater checks cover this fix; native Windows layout verification remains pending.

# v0.27.0 — CPU tuning readiness

Adds a CPU tuning page with Windows-reported CPU, board and BIOS inventory, explicit per-control availability, vendor requirements, JSON export and direct access to the existing three-run CPU baseline. Intel model-pattern matches are candidates only; no BIOS or write capability is inferred. Direct CPU clock, voltage and power-limit changes are not implemented.

Tests passed on Linux for classification, mocked UI dispatch/locks/export, endurance and guided-clock handlers, repeated tests, updater, PowerShell syntax and XAML wiring. Windows UI validation remains pending. The user confirmed v0.26.1 GPU endurance completion, Stop, persistence after reopen and a 10-minute run without reported errors; these confirm that workflow on one PC, not overclock stability.

# v0.26.1 — Endurance Stop button fix

Refresh endurance controls after the background job is assigned so Stop and save result enables during a run and duration buttons lock. Also refresh after starting an update. Cancel task already uses the same graceful partial-result path for endurance. Regression coverage now executes the actual Start-Task handler with mocked worker creation. Windows button interaction still needs user validation.

# v0.26.0 — GPU endurance observation

- Adds 5- and 10-minute GPU shader-load sessions under Benchmark, with progress and matched GPU temperature monitoring.
- Stop saves a partial result with its stop reason. Interrupted runs are identified after restart.
- Stops on sampled 85 C CPU/GPU temperatures, invalid/missing/slow GPU telemetry, workload errors or stalled progress. Native sensor heartbeat expires between rendering batches.
- Uses current settings without clock writes or automatic restoration. Use Tuning to restore saved offsets. Completion does not prove stability and does not produce a comparable benchmark score.

Validation: Linux mocked hardware tests and existing guided-clock, updater, repeatability and results regression checks passed. Native Windows/WPF rendering, physical GPU endurance and installation of this release are not yet validated. A driver hang can delay stopping. No pixel, VRAM integrity, WHEA, driver-reset-log or game validation is performed.

# v0.25.0 - Guided core trial and dashboard candidate

- Restyles Overview around the supplied reference: navy surfaces, purple navigation, CPU/GPU/memory illustrations, larger readings and a combined latest-session/chart card. All existing navigation and controls remain available.
- Adds a reviewed +15 MHz NVIDIA core trial: three baseline runs, three retests, then Keep or Restore. Memory offset stays unchanged.
- Checks GPU identity, driver, power plan, power limit, offsets and benchmark compatibility before comparing shader throughput and sampled GPU temperature peaks.
- Attempts restoration on cancellation or failed retests; preserves saved originals when restoration cannot be verified. Relaunch requests recovery without writing GPU settings automatically.
- Fixes the footer claiming no settings changed after manual clock writes.
- Linux PowerShell workflow tests use mocked GPU controls. Windows WPF and the full physical guided trial still require validation before publication; this is not a stability certification.

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
