# Development workflow

## Branches

- `main` contains the source of the released app, currently v0.22.2.
- `develop` is the integration branch for ongoing work. It includes the unreleased GPU clock controls and comparison-report work.
- Create short-lived `feature/<name>` and `fix/<name>` branches from `develop`, then merge reviewed changes into `develop`.
- For a release, validate `develop`, merge it into `main`, tag the release commit with `v<version>`, and publish the packaged app and update manifest.

The releases through v0.22.1 were distributed as ZIP assets before the complete source was imported into this repository. Their existing tags remain unchanged. Use their `PC-Insight-Windows-Preview.zip` assets for the complete historical versions.

## Running and checking the app

Use Windows PowerShell 5.1 and the included `Start-PC-Insight.cmd` launcher. Dependencies and their license notices are included under `vendor/`. See README.md for hardware and driver requirements.

Run the relevant scripts in `tests/` with Windows PowerShell 5.1. Tests that load WPF need `-STA`. For example:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-SessionComparison.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-SessionComparisonUI.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-ComparisonWorkflow.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Interface.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Updates.ps1
```

Mock and interface tests do not replace checking hardware readings and interaction on Windows. Review each test's prerequisites before running it.

## Releases and updater

Package the app inside a single top-level `PC-Insight/` directory. Keep all dependencies and their notices. Attach `PC-Insight-Windows-Preview.zip` and `update.json` to the GitHub Release. Keep `version.json` and the manifest version consistent, and recalculate the ZIP's SHA-256 and byte count after packaging.

The public update feed is `https://github.com/IGN1TE/pc-insight/releases/latest/download/update.json`. Branch changes alone do not publish an update. Verify the publicly downloaded manifest and archive after publishing.

Saved sessions, exported hardware reports, settings and recovery records belong on the user's PC and must not be included in source commits or release assets.

## Branding

The PNG logo and matching icon are under `assets/branding/`. They are transparent raster assets generated with the built-in ImageGen tool. The prompt set is saved alongside them. `Branding.ps1` loads the logo into WPF using absolute paths so shortcuts can start from another working directory. `assets/branding/Build-Icon.ps1` creates the multi-size Windows icon; the installer uses a release-specific icon filename for Windows shell integration.

## Current development preview

`feature/gpu-oc-trials` builds v0.28.0 on `develop` (v0.24.1). The public release is v0.24.1. This branch adds repeated measured clock trials and automatic restoration; pushing the branch is not a release.

Run `tests/Test-GpuClockTrial.ps1`, `tests/Test-GpuTrialWorkloadGuard.ps1` and `tests/Test-GpuClockTrialUI.ps1` alongside the existing GPU/recovery suites. The Windows workflow runs PowerShell 5.1 and real hidden WPF handlers with simulated jobs and GPU calls. It never changes host clocks. Linux checks cover the workflow/journal logic and simulated workload guards but do not validate WPF or Windows driver behavior.

The earlier read-only probe loaded the installed NVIDIA library and read offsets on the target RTX 5090. Physical writes, artifact behavior, real thermal response and overclock stability remain unverified. Before publishing, validate a small reviewed change on the target PC, cancel during the retest, confirm both original offsets, exercise close/relaunch and inspect the saved report. Do not infer hardware compatibility from mock CI results.

Trial recovery is owned by `gpu-clock-restore.json`. The last result is saved separately in `gpu-clock-trial.json`. A failed or cancelled baseline performs no clock writes. A trial never starts with an existing recovery record. Normal close requests cooperative cancellation and waits; force termination/driver hangs/power loss can leave recovery pending. Startup only displays saved state and never writes clocks automatically.

The default trial uses three runs at each setting. Schema 2 saves `BeforeRuns`/`AfterRuns`, eligible-run summaries, power-setting snapshots, and comparison reasons. Run boundaries check the Windows plan and selected GPU power limit; management queries are outside the scored workload. A >5% baseline spread aborts before any write. Retest spread, range overlap and >5 C median starting-temperature difference label completed comparisons inconclusive. Quick one-pair mode is also inconclusive for repeatability. Prior schema-1 reports remain displayable; no migration writes hardware.

Trial history is implemented in `GpuClockTrialHistory.ps1` and `GpuClockTrialHistoryUI.ps1`. Archives use the trial GUID as their filename under `gpu-clock-trials/`, outside the recovery journal. Archival never writes GPU settings or deletes old experiments. Startup/import normalizes unfinished checkpoints to Interrupted/Unverified and never overwrites a final archived outcome with that older checkpoint. A failed pre-start archive aborts before clocks change; a failed post-trial archive cannot bypass restoration. Run `tests/Test-GpuClockTrialHistory.ps1` for archive and comparison regression coverage; `Test-GpuClockTrialUI.ps1` also exercises actual history selectors, input-only loading and export snapshots under WPF.

`GpuClockTrialTelemetry.ps1` copies workload result frames into per-run telemetry schema 1: up to 16 fully identified GPU channels plus 64 timestamped value vectors. The existing trial schema 2 remains readable; telemetry is optional. `GpuClockTrialTelemetryUI.ps1` renders only the selected saved experiment. Source queries are not repeated, and these handlers never call a driver or workload. Identically named GPU sensor parents are rejected rather than merged; query issues and invalid values become gaps. Trial persistence uses JSON depth 10 to preserve the nested vectors. Run `tests/Test-GpuClockTrialTelemetry.ps1`; the workflow also exercises real WPF selection/redraw/legacy clearing in `Test-GpuClockTrialUI.ps1`. Mock validation is not physical sensor accuracy or OC stability validation.
