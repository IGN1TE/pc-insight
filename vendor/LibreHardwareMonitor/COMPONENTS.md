# Bundled components

LibreHardwareMonitorLib 0.9.6 and accompanying runtime DLLs were extracted unmodified from:
https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip

Upstream source is included in LibreHardwareMonitor-0.9.6-source.zip, also available from:
https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/tree/v0.9.6

LibreHardwareMonitorLib: MPL-2.0 (LICENSE).
Embedded PawnIO.Modules: LGPL-2.1, upstream terms in THIRD-PARTY-NOTICES.txt; module project: https://github.com/namazso/PawnIO.Modules . The system PawnIO driver/installer is not bundled or installed.

HidSharp 2.6.4: see notices/hidsharp-LICENSE.txt and package metadata.
RAMSPDToolkit-NDD 1.4.2: MPL-2.0, source https://github.com/Blacktempel/RAMSPDToolkit/tree/3b47b960e0830fef344624ad5e389675d5f0a1ce
DiskInfoToolkit 1.1.2: MPL-2.0, source https://github.com/Blacktempel/DiskInfoToolkit/tree/25319eae5781e75bcf141e844ceab2afe94d40ea
BlackSharp.Core 1.0.7: MPL-2.0, source https://github.com/Blacktempel/BlackSharp/tree/c70b735c6cec123ee8a046ac4a0bc6c606f52cf0
The exact NuGet metadata for these dependencies is included in notices.

Microsoft.Bcl.*, System.* runtime support assemblies: Microsoft/.NET Foundation and contributors; MIT license text in notices/Microsoft-DotNet-LICENSE.txt. Source: https://github.com/dotnet/runtime . These are bundled from the official Libre release to retain its compatible dependency set.

DLL SHA-256 hashes are listed in hashes.json. No vendor executable, driver installer, GUI plugin or third-party binary has been modified. Retain these notices and source-access information when redistributing.
