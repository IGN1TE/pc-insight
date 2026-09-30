# Development workflow

## Branches

- `main` contains the source of the released app, currently v0.22.2.
- `develop` is the integration branch for ongoing work. It starts at the same source as `main`.
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

`feature/nvidia-clock-offsets` contains the v0.24.1 candidate built from the supplied v0.24.0 preview. It adds Windows validation, a final temperature check before applying GPU clock offsets, and clock-recovery protection during uninstall. The public release remains v0.22.2 until a candidate is published.

The Windows mock suites include `tests/Test-GpuOverclock.ps1`, `tests/Test-GpuOverclockUI.ps1`, `tests/Test-ClockComparisonContext.ps1`, `tests/Test-UninstallRecovery.ps1`, and the existing comparison/interface/updater regressions. The read-only probe loaded the installed NVIDIA library and read offsets on the target RTX 5090. This does not validate physical writes or overclock stability.