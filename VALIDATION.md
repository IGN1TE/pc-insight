# 0.29.0 candidate validation — 2026-10-10

Base: published v0.28.1, commit 210992caef9ba9a745c99e6106574374ab46ced8.

- Portable full regression runner: **37 passed, 5 skipped, 0 failed** on PowerShell 7/Linux. Includes bounded real CPU/RAM workers and mocked CPU/GPU tuning, recovery, comparison, updater and UI handlers.
- Windows-only skipped suites: Interface, GpuOverclockUI, ComparisonWorkflow, SessionComparisonUI and NativeSensors. No Windows CI execution is claimed.
- New evidence checks cover empty logs, access failures, error classification, interval bounds, truncated results, raw-message privacy and legacy sessions.
- New result-panel checks cover partial/completed sessions, event warning labels, filtering, refresh selection retention, expired selection, cancelled saves and export snapshot preservation.
- Endurance orchestration additionally verifies that evidence collection failure does not discard workload results; existing thermal/sensor/cancel/heartbeat tests pass.
- All PowerShell files parse; both XAML documents parse; app control bindings and duplicate names checked.
- Release ZIP rebuilt from tracked files; vendor hashes and each archived file verified. Actual updater manifest parser and extraction round trip checked separately before delivery.

Still pending: Windows PowerShell 5.1 full suite, native WPF appearance/interactions, real System log access, actual GPU workload acceptance and installation. See TEST-TONIGHT.md.

Publishing is blocked: GitHub integration returns HTTP 403 Resource not accessible by integration on branch/tree writes. No new remote branch, release or update-feed change was created. The candidate kit preserves the unpublished work.
