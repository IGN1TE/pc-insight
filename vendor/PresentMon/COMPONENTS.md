PresentMon standalone console 2.6.0 x64 (MIT), Copyright Intel Corporation.
Source and release: https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0
Binary: PresentMon-2.6.0-x64.exe
Upstream SHA-256: b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af
Upstream size: 980320 bytes. Verified against the GitHub release asset digest.

Used only while the PC Insight game overlay is visible, with one target process,
a unique ETW session, CSV output to a pipe, and v1 metrics. No CSV files or
PresentMon service are installed. PC Insight checks the executable hash before use.
The overlay reports application presentation FPS from the busiest observed swap chain
over approximately two seconds; this is not displayed/generated-frame FPS.

Upstream console options: https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md
Upstream v1 column definitions: https://github.com/GameTechDev/PresentMon/blob/v1.9.2/README.md

PC Insight 0.21.2 uses the normal GPU/display tracking configuration; only input
tracking is disabled. This replaces the reduced capture mode used in 0.21.0/0.21.1.
The bundled executable and its pinned upstream hash are unchanged.
