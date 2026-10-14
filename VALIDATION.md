# 0.32.0 validation

- Portable PowerShell 7: 41 passed, 6 Windows-only suites skipped, 0 failed.
- New scanner transaction and UI handler suites cover bounded progression, recommendations, cancellation, restart and restoration failures with mocked hardware.
- Full Windows PowerShell 5.1/WPF and package gate pending. Physical GPU acceptance pending.

# 0.31.0 validation — 2026-10-10

- Portable runner: 39 passed, 6 Windows-only suites skipped, 0 failed.
- New report regression checks cover stopped/legacy evidence, failed-sample exclusion, sensor coverage, missing values, HTML encoding, absence of active/external content, atomic replacement and existing-file preservation on errors.
- Windows UI coverage exercises the real report button and verifies that selection and comparison-history changes during Save cannot alter the exported snapshot.
- Final Windows PowerShell 5.1 CI: **45 passed, 0 skipped, 0 failed**. Run: https://github.com/IGN1TE/pc-insight/actions/runs/38065051650 . Source: `392bc15e707ba68b95f5874e6cc4357c6ffcd8b6`. Package integrity and actual updater extraction passed. The public latest feed and ZIP were verified byte-for-byte against the CI artifact after publication.
- Target-PC installation and native Save/Print acceptance remain pending.

# 0.30.0 validation — 2026-10-10

- Portable runner: 38 passed, 6 Windows-only suites skipped, 0 failed.
- Tests cover pinned/recent retention, immutable note updates, literal search and combined filters, pin/note limits, legacy state labels, JSON persistence and unreadable-history preservation.
- New Windows UI suite exercises real controls and actual main-window handlers: selection retention, filtered comparison references, note/pin clicks, empty states, exports during jobs, modal snapshot consistency, failed writes and unsaved drafts during refresh.
- Initial Windows feature checkpoint: 44 passed, 0 skipped, 0 failed. Windows rendering identified cramped minimum-size content; the whole results page now scrolls. Final Windows run 38064394416 passed all 44 suites plus package validation. The published feed and ZIP matched that CI artifact.
- Target-PC appearance and installation still need acceptance; see TEST-TONIGHT.md.

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
