# 0.30.0 development checkpoint

Continue from `release/v0.30.0-result-library`, based on published v0.29.0. SessionLibrary.ps1 handles retention and immutable annotations. SessionLibraryUI.ps1 binds filters, notes and pins; main-window selection updates charts/exports. The persisted sessions.json format remains an array with optional Pinned and Note fields. At most 20 new pins are allowed, but pre-existing extra pins are never discarded automatically. Unpin does not immediately prune data; retention runs when a new session arrives.

# Development and releases

The published baseline for this candidate is v0.28.1 on `release/v0.28.1-cpu-results` (210992caef9ba9a745c99e6106574374ab46ced8). `main` still points to v0.22.2; do not start new development there and accidentally discard newer features. The 0.29.0 source is on `release/v0.29.0-validation` on GitHub. When the connected integration rejected writes, the authorized signed-in GitHub website upload route succeeded.

## Validation

Run all regression suites in isolated Windows PowerShell 5.1 processes:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/Test-Release.ps1
```

The runner parses all scripts and both XAML documents, then discovers `tests/Test-*.ps1`. A failing suite fails the run. Hardware writes are mocked. The bounded CPU and RAM worker tests execute their actual workloads; WPF tests load windows without starting the app. Windows validation does not certify physical tuning or stability.

On Linux, PowerShell 7 can run `tools/Test-Release.ps1 -Portable`. Six Windows-specific suites are explicitly skipped. The GitHub Actions workflow runs the full Windows suite on push to main, develop, release, feature and fix branches, and on pull requests. The first full Windows run passed all 42 suites and the updater/package checks: https://github.com/IGN1TE/pc-insight/actions/runs/38062748711 .

## Packaging

Commit the intended source, then run:

```text
python tools/Build-Release.py --output outputs/release
```

The builder includes only tracked root app files and assets/vendor content, checks LibreHardwareMonitor dependency hashes, creates one `PC-Insight/` archive root, checks every archived file's hash, and emits an update manifest and package audit. Developer tests, workflows, local user data, settings and recovery records are excluded. The audit records the source commit and whether tracked work differs from it.

CI also exercises the application's update manifest parser and archive extractor. Successful CI uploads a candidate artifact; it does not automatically publish a public release. Publish the exact validated archive and matching `update.json` together. Verify the public feed and archive after publication. The feed remains `https://github.com/IGN1TE/pc-insight/releases/latest/download/update.json`.

## Event evidence

`Reliability.ps1` reads only the System log, with explicit start/end bounds, at most 101 queried events per provider and 100 retained event references per provider. WHEA-Logger and Display 4101 are separate checks. Unknown/provider/access errors remain unavailable, while only Get-WinEvent's specific no-match error becomes an empty result. Workload results survive evidence failures. Evidence is collected after stopping GPU load; late events or cleared logs can be missed. Raw messages and machine/user identity are not exported. See Microsoft Get-WinEvent documentation: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1

## Existing development constraints

Preserve recovery journals and readback checks. No unvalidated CPU ratio or voltage writes. Do not mark hardware validation complete based on mocked tests. Branding sources remain in `assets/branding/`; dependencies and notices remain in `vendor/`. Follow the bundled TEST-TONIGHT.md for manual acceptance.
