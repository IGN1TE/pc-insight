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
