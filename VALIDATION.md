# 0.29.0 validation — 2026-10-10

Base: published v0.28.1, commit 210992caef9ba9a745c99e6106574374ab46ced8.

- Portable full regression runner: **37 passed, 5 skipped, 0 failed** on PowerShell 7/Linux. Includes bounded real CPU/RAM workers and mocked CPU/GPU tuning, recovery, comparison, updater and UI handlers.
- Windows PowerShell 5.1 CI: **42 passed, 0 skipped, 0 failed**, including Interface, GpuOverclockUI, ComparisonWorkflow, SessionComparisonUI and NativeSensors. Run: https://github.com/IGN1TE/pc-insight/actions/runs/38062748711 .
- New evidence checks cover empty logs, access failures, error classification, interval bounds, truncated results, raw-message privacy and legacy sessions.
- New result-panel checks cover partial/completed sessions, event warning labels, filtering, refresh selection retention, expired selection, cancelled saves and export snapshot preservation.
- Endurance orchestration additionally verifies that evidence collection failure does not discard workload results; existing thermal/sensor/cancel/heartbeat tests pass.
- All PowerShell files parse; both XAML documents parse; app control bindings and duplicate names checked.
- Release ZIP rebuilt from tracked files; vendor hashes and each archived file verified. Actual updater manifest parser and extraction round trip checked separately before delivery.

Still pending: target-PC native WPF appearance/interactions, real System log access, actual GPU workload acceptance and installation. See TEST-TONIGHT.md.

Source upload succeeded through the signed-in GitHub website after integration writes returned HTTP 403. The full uploaded tree matches the locally tested source. Windows CI additionally built and audited the ZIP and passed the actual update manifest parser and extraction checks. Release assets must be published together and verified against the public feed.
