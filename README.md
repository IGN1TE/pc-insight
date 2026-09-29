# PC Insight for Windows

PC Insight is a Windows PowerShell/WPF preview app for inventory, sensor monitoring, benchmarks, and reviewed tuning. Each release ZIP includes the app source, installer, tests, dependencies, and license notices.

## Install once

1. Download **PC-Insight-Windows-Preview.zip** from [the latest release](https://github.com/IGN1TE/pc-insight/releases/latest). Do not use the automatic Source code archives as the installer.
2. Extract the complete ZIP and close PC Insight.
3. Run `PC-Insight/Install-PC-Insight.cmd`.
4. Use the desktop or Start menu shortcut.

App files install under `%LOCALAPPDATA%\Programs\PCInsight`. Saved results, profiles, and recovery records remain under `%LOCALAPPDATA%\PCInsight`.

## Future updates

Open **Updates**, choose **Save feed and check**, then **Download update** and **Install and restart** when a newer version is available. The GitHub feed is prefilled; existing saved feed settings take precedence. No GitHub account or token is needed by the updater. Checks are manual and only strictly higher versions are offered.

Feed: `https://github.com/IGN1TE/pc-insight/releases/latest/download/update.json`

## Publishing the next version

Create a release with a new version tag and attach both `PC-Insight-Windows-Preview.zip` and `update.json`. Keep the ZIP top-level `PC-Insight/` folder and all dependency notices. Recalculate SHA-256 and exact byte size after final package changes. Never include saved user data or reports.

The manifest fields are `schema: 1`, `appId: "PCInsight.PerUser"`, `version`, a tag-specific HTTPS `downloadUrl`, `sha256`, and `sizeBytes`. The manifest and packaged `version.json` must agree. The feed follows the latest published non-prerelease GitHub Release; PC Insight itself remains preview software.

## Verification

Windows PowerShell 5.1 checks passed for updater version comparisons, redirects, archive paths, final ZIP extraction, dependency hashes, and rejection of wrong checksums, sizes, and package versions. Anonymous public feed and ZIP downloads were independently verified against the final manifest. Live PowerShell networking encountered a TLS error in the restricted validation session; full in-app installation and restart remain unverified.

The app and feed are unsigned. SHA-256 validates consistency with the feed, not a publisher signature. See the packaged README for hardware requirements and feature limitations.
