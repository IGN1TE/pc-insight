# PC Insight branding

- `pc-insight-logo-v1.png`: horizontal logo and wordmark; transparent PNG.
- `pc-insight-icon-v1.png`: matching standalone symbol; transparent PNG.
- `logo-prompts.txt`: creation prompts used with the built-in ImageGen tool.

The identity uses a violet frame, rising performance bars and a cyan accent. Keep the proportions intact and allow clear space around the artwork. The PNG files are raster artwork, not editable vector masters.

From v0.22.2, the logo appears in the sidebar and About page. `Build-Icon.ps1` encodes the matching PNG symbol into the root `PCInsight.ico`, with 16, 20, 24, 32, 40, 48, 64, 128 and 256 pixel frames. It uses Windows WPF to resample the approved artwork; it does not generate a different design. Run with Windows PowerShell 5.1 and `-STA` after an approved icon artwork change.

The installer copies the ICO to a filename containing the installed release version and uses it for desktop/Start menu shortcuts and Installed Apps. This avoids reusing the old icon-cache path.
