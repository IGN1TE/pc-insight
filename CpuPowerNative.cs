// PC Insight's limited PawnIO client. The device protocol is documented upstream:
// https://github.com/namazso/PawnIO/blob/master/PawnIO/include/pawnio_um.h
// https://github.com/namazso/PawnIO.Modules/blob/0.2.11/IntelMSR.p
// No driver is installed here. Only the hash-pinned, upstream signed module is loaded.
using System;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class PCCpuPowerRegisters
{
    public string RawLimitHex { get; set; }
    public string RawUnitsHex { get; set; }
    public double PL1Watts { get; set; }
    public double PL2Watts { get; set; }
    public bool Locked { get; set; }
    public bool PL1Enabled { get; set; }
    public bool PL2Enabled { get; set; }
}

public static class PCCpuPowerNative
{
    public const string ModuleSha256 = "d6ed85d65ab17a22f813ef98207d6d537155ee2ded5976a21cb48413c9b92e5f";
    public const ulong WritableMask = 0x00007FFF00007FFFUL;
    private const uint LoadIoctl = (41394U << 16) | (0x821U << 2);
    private const uint ExecuteIoctl = (41394U << 16) | (0x841U << 2);
    private const uint PackageLimit = 0x610;
    private const uint PowerUnits = 0x606;

    [StructLayout(LayoutKind.Sequential)]
    private struct GroupAffinity
    {
        public UIntPtr Mask;
        public ushort Group;
        public ushort Reserved0, Reserved1, Reserved2;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
        byte[] input, uint inputLength, byte[] output, uint outputLength,
        out uint returned, IntPtr overlapped);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetThreadGroupAffinity(IntPtr thread,
        ref GroupAffinity affinity, out GroupAffinity previous);

    public static ulong ParseHex(string raw)
    {
        ulong value;
        if (raw == null || raw.Length != 16 ||
            !UInt64.TryParse(raw, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out value))
            throw new ArgumentException("CPU register value must contain exactly 16 hexadecimal characters.");
        return value;
    }

    public static PCCpuPowerRegisters Decode(string limitHex, string unitsHex)
    {
        ulong limit = ParseHex(limitHex), units = ParseHex(unitsHex);
        if ((units & ~0x00000000000F1F0FUL) != 0)
            throw new InvalidOperationException("Unexpected CPU power-unit register layout; power writes are unavailable.");
        double unit = Math.Pow(2.0, -(int)(units & 15));
        return new PCCpuPowerRegisters {
            RawLimitHex = limit.ToString("X16", CultureInfo.InvariantCulture),
            RawUnitsHex = units.ToString("X16", CultureInfo.InvariantCulture),
            PL1Watts = (limit & 0x7FFF) * unit,
            PL2Watts = ((limit >> 32) & 0x7FFF) * unit,
            Locked = (limit & (1UL << 63)) != 0,
            PL1Enabled = (limit & (1UL << 15)) != 0,
            PL2Enabled = (limit & (1UL << 47)) != 0
        };
    }

    // Also used by offline regression tests. It never accesses hardware.
    public static void ValidateChange(string currentHex, string expectedHex, string targetHex)
    {
        ulong current = ParseHex(currentHex), expected = ParseHex(expectedHex), target = ParseHex(targetHex);
        if (current != expected)
            throw new InvalidOperationException("CPU power limits changed since review; rescan before applying or restoring.");
        if ((current & (1UL << 63)) != 0)
            throw new InvalidOperationException("CPU package power limits are firmware locked; no write was attempted.");
        if ((current & (1UL << 15)) == 0 || (current & (1UL << 47)) == 0)
            throw new InvalidOperationException("Both firmware power limits must already be enabled; PC Insight will not enable them.");
        if (((current ^ target) & ~WritableMask) != 0)
            throw new InvalidOperationException("Only the two power-limit wattage fields may change; enable, clamp, time and lock bits must be preserved.");
        if ((target & 0x7FFF) == 0 || ((target >> 32) & 0x7FFF) == 0)
            throw new InvalidOperationException("Zero CPU package power limits are not supported.");
    }

    public static PCCpuPowerRegisters Read(string modulePath)
    {
        return WithAffinity(delegate {
            using (SafeFileHandle handle = OpenModule(modulePath)) {
                ulong units = ReadRegister(handle, PowerUnits);
                ulong limit = ReadRegister(handle, PackageLimit);
                return Decode(limit.ToString("X16"), units.ToString("X16"));
            }
        });
    }

    public static string Write(string modulePath, string expectedHex, string targetHex)
    {
        // Invalid inputs fail before native calls.
        ParseHex(expectedHex); ParseHex(targetHex);
        return WithAffinity(delegate {
            using (SafeFileHandle handle = OpenModule(modulePath)) {
                ulong units = ReadRegister(handle, PowerUnits);
                ulong current = ReadRegister(handle, PackageLimit);
                Decode(current.ToString("X16"), units.ToString("X16"));
                ValidateChange(current.ToString("X16"), expectedHex, targetHex);
                ulong target = ParseHex(targetHex);
                if (current != target)
                    Execute(handle, "ioctl_write_msr", new ulong[] { PackageLimit, target }, 0);
                ulong readback = ReadRegister(handle, PackageLimit);
                if (readback != target)
                    throw new InvalidOperationException("CPU power-limit readback did not match the requested value. Requested " +
                        target.ToString("X16") + ", observed " + readback.ToString("X16") + ". Restoration may be needed.");
                return readback.ToString("X16", CultureInfo.InvariantCulture);
            }
        });
    }

    private static SafeFileHandle OpenModule(string path)
    {
        byte[] module = File.ReadAllBytes(path);
        using (SHA256 hash = SHA256.Create()) {
            string actual = BitConverter.ToString(hash.ComputeHash(module)).Replace("-", "").ToLowerInvariant();
            if (!String.Equals(actual, ModuleSha256, StringComparison.Ordinal))
                throw new InvalidOperationException("CPU power module integrity check failed. Reinstall the verified PC Insight release.");
        }
        SafeFileHandle handle = CreateFile(@"\\?\GLOBALROOT\Device\PawnIO", 0xC0000000U, 7U,
            IntPtr.Zero, 3U, 0x80U, IntPtr.Zero);
        if (handle.IsInvalid) {
            int code = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(code, "Cannot open the installed PawnIO driver. Run PC Insight as administrator and check that its sensor driver is installed and running; no driver was installed by this action.");
        }
        try {
            uint returned;
            if (!DeviceIoControl(handle, LoadIoctl, module, (uint)module.Length, null, 0, out returned, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The installed PawnIO driver rejected the signed CPU power module.");
            if (returned != 0)
                throw new InvalidOperationException("Unexpected PawnIO module-load response.");
            return handle;
        } catch { handle.Dispose(); throw; }
    }

    private static ulong ReadRegister(SafeFileHandle handle, uint address)
    {
        if (address != PackageLimit && address != PowerUnits)
            throw new InvalidOperationException("CPU power adapter register is not allowlisted.");
        return BitConverter.ToUInt64(Execute(handle, "ioctl_read_msr", new ulong[] { address }, 8), 0);
    }

    private static byte[] Execute(SafeFileHandle handle, string name, ulong[] values, int outputBytes)
    {
        // This helper is private and only receives the fixed read/write requests above.
        byte[] input = new byte[32 + values.Length * 8];
        Encoding.ASCII.GetBytes(name).CopyTo(input, 0);
        for (int i = 0; i < values.Length; i++)
            BitConverter.GetBytes(values[i]).CopyTo(input, 32 + i * 8);
        byte[] output = outputBytes == 0 ? null : new byte[outputBytes];
        uint returned;
        if (!DeviceIoControl(handle, ExecuteIoctl, input, (uint)input.Length,
                output, (uint)outputBytes, out returned, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "PawnIO CPU power " + name + " failed; the operation was not verified.");
        if (returned != (uint)outputBytes)
            throw new InvalidOperationException("PawnIO returned an incomplete CPU register response; no value is inferred.");
        return output;
    }

    private static T WithAffinity<T>(Func<T> operation)
    {
        if (Environment.OSVersion.Platform != PlatformID.Win32NT || IntPtr.Size != 8)
            throw new PlatformNotSupportedException("CPU power control requires 64-bit Windows PowerShell.");
        Thread.BeginThreadAffinity();
        GroupAffinity previous = new GroupAffinity();
        bool changed = false;
        Exception failure = null;
        T value = default(T);
        try {
            GroupAffinity requested = new GroupAffinity { Mask = new UIntPtr(1), Group = 0 };
            if (!SetThreadGroupAffinity(GetCurrentThread(), ref requested, out previous))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot select CPU group 0, processor 0; power control was not attempted.");
            changed = true;
            value = operation();
        } catch (Exception error) { failure = error; }
        finally {
            try {
                if (changed) {
                    GroupAffinity ignored;
                    if (!SetThreadGroupAffinity(GetCurrentThread(), ref previous, out ignored)) {
                        Exception restore = new Win32Exception(Marshal.GetLastWin32Error(), "CPU control could not restore the calling thread's processor affinity.");
                        failure = failure == null ? restore : new AggregateException(failure, restore);
                    }
                }
            } finally { Thread.EndThreadAffinity(); }
        }
        if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
        return value;
    }
}
