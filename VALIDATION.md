# 0.32.1 validation

- Focused synthetic native-sensor-to-scan regression passed: CPU-only warning, GPU baseline review, retained GPU statistics, blocked CPU/RAM load, real provider failures, missing GPU data, slow queries and both thermal cutoffs.
- Actual scan UI handler regression passed with missing-CPU warning in the review prompt.
- Windows run https://github.com/IGN1TE/pc-insight/actions/runs/38633124653 passed 48 suites, zero skipped/failed, plus package/updater extraction.
- Published v0.32.1 source: b55a493854168945bc6a79a54f7c09f58d76a83d. Public latest feed and ZIP exactly matched the Windows CI artifact. ZIP SHA256 116e65e8be31c060a45b7f81dadf9e50da29b48faee2be0852f78a013e492392; 8,645,894 bytes.
- Target-PC retry pending. CPU temperature access remains unavailable in the reported data; no driver fix is claimed.

# 0.32.0 validation

- Portable PowerShell 7: 41 passed, 6 Windows-only suites skipped, 0 failed.
- New scanner transaction and UI handler suites cover bounded progression, recommendations, cancellation, restart and restoration failures with mocked hardware.
- Windows PowerShell 5.1/WPF: 47 passed, zero skipped/failed; package and updater extraction passed. Run https://github.com/IGN1TE/pc-insight/actions/runs/38629660959 .
- Published tag v0.32.0 targets c6c6bfef7a3b9fcdda81df96773f4bb286e06a8e. Public latest feed and ZIP verified byte-for-byte against that Windows CI artifact. ZIP SHA256: a7f6ef1d01450749c816b103b150f322b802299d103f783ab32e4d47bacf733e; 8,644,694 bytes.
- Physical GPU scan acceptance remains pending.

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
