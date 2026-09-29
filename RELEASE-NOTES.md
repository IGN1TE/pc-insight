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
