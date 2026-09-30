using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

// ABI from NVIDIA's public nvmlClockOffset_v1_t (NVML R555+). No private NVAPI calls.
[StructLayout(LayoutKind.Sequential, Pack=4)]
public struct PCNvmlClockOffset {
    public uint Version, Type, Pstate;
    public int OffsetMHz, MinMHz, MaxMHz;
    public static PCNvmlClockOffset Create(uint domain) {
        return new PCNvmlClockOffset { Version=(uint)Marshal.SizeOf(typeof(PCNvmlClockOffset)) | (1U<<24), Type=domain, Pstate=0 };
    }
}
public sealed class PCNvidiaClockDevice {
    public string UUID,Name,Driver,Issue="",TemperatureIssue="";
    public int CoreMHz,MemoryMHz,CoreMin,CoreMax,MemoryMin,MemoryMax;
    public uint? TemperatureC;
    public bool Available;
    public string Label {get{return Name+" | "+UUID;}}
}
public static class PCNvidiaClockNative {
    static readonly object gate=new object();
    static IntPtr library;
    static bool initialized;
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
    [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Init();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Count(out uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ByIndex(uint index,out IntPtr device);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ById([MarshalAs(UnmanagedType.LPStr)] string uuid,out IntPtr device);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DeviceText(IntPtr device,StringBuilder text,uint length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SystemText(StringBuilder text,uint length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Clock(IntPtr device,ref PCNvmlClockOffset offset);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Temperature(IntPtr device,uint sensor,out uint value);
    static Count count;static ByIndex byIndex;static ById byId;static DeviceText uuidText,nameText;
    static SystemText driverText;static Clock getClock,setClock;static Temperature temperature;
    static T Resolve<T>(string name) where T:class {
        IntPtr pointer=GetProcAddress(library,name);
        if(pointer==IntPtr.Zero)throw new NotSupportedException("Installed NVIDIA driver does not expose "+name+". Clock controls are unavailable.");
        return Marshal.GetDelegateForFunctionPointer(pointer,typeof(T)) as T;
    }
    static void Check(int code,string operation) {
        if(code==0)return;
        string reason=code==3 ? "not supported by this GPU/driver" : code==4 ? "administrator permission required" : code==15 ? "GPU unavailable or driver reset" : code==25 ? "driver structure version unsupported" : "NVIDIA status "+code;
        throw new InvalidOperationException(operation+": "+reason+".");
    }
    static void Initialize() {
        if(initialized)return;
        if(Environment.OSVersion.Platform!=PlatformID.Win32NT || !Environment.Is64BitProcess)throw new NotSupportedException("GPU clock control requires 64-bit Windows PowerShell.");
        if(library==IntPtr.Zero){
            string[] paths={Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"nvml.dll"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"NVIDIA Corporation","NVSMI","nvml.dll")};
            foreach(string path in paths){if(File.Exists(path)){library=LoadLibraryEx(path,IntPtr.Zero,0x100U|0x800U);if(library!=IntPtr.Zero)break;}}
            if(library==IntPtr.Zero)throw new NotSupportedException("Installed NVIDIA management library was not found in a supported driver location.");
        }
        count=Resolve<Count>("nvmlDeviceGetCount_v2");byIndex=Resolve<ByIndex>("nvmlDeviceGetHandleByIndex_v2");byId=Resolve<ById>("nvmlDeviceGetHandleByUUID");
        uuidText=Resolve<DeviceText>("nvmlDeviceGetUUID");nameText=Resolve<DeviceText>("nvmlDeviceGetName");driverText=Resolve<SystemText>("nvmlSystemGetDriverVersion");
        getClock=Resolve<Clock>("nvmlDeviceGetClockOffsets");setClock=Resolve<Clock>("nvmlDeviceSetClockOffsets");temperature=Resolve<Temperature>("nvmlDeviceGetTemperature");
        Check(Resolve<Init>("nvmlInit_v2")(),"Initialize NVIDIA management");initialized=true;
        // Loaded once for app lifetime. No NVIDIA library is bundled or downloaded.
    }
    static string Text(IntPtr device,DeviceText getter){var text=new StringBuilder(256);Check(getter(device,text,256),"Read GPU identity");return text.ToString();}
    static PCNvmlClockOffset ReadOffset(IntPtr device,uint domain){
        var value=PCNvmlClockOffset.Create(domain);Check(getClock(device,ref value),"Read "+(domain==0 ? "core" : "memory")+" P0 offset");
        if(value.Version!=PCNvmlClockOffset.Create(domain).Version || value.Type!=domain || value.Pstate!=0 || value.MinMHz>value.MaxMHz || value.OffsetMHz<value.MinMHz || value.OffsetMHz>value.MaxMHz)throw new InvalidOperationException("Driver returned inconsistent clock offset data.");
        return value;
    }
    static PCNvidiaClockDevice ReadHandle(IntPtr device){
        var result=new PCNvidiaClockDevice { UUID=Text(device,uuidText),Name=Text(device,nameText) };
        var driver=new StringBuilder(256);Check(driverText(driver,256),"Read NVIDIA driver version");result.Driver=driver.ToString();
        try{
            var core=ReadOffset(device,0);var memory=ReadOffset(device,2);
            result.CoreMHz=core.OffsetMHz;result.MemoryMHz=memory.OffsetMHz;result.CoreMin=core.MinMHz;result.CoreMax=core.MaxMHz;result.MemoryMin=memory.MinMHz;result.MemoryMax=memory.MaxMHz;result.Available=true;
        }catch(Exception e){result.Issue=e.Message;}
        uint temp;int code=temperature(device,0,out temp);
        if(code==0 && temp>0 && temp<125)result.TemperatureC=temp;else result.TemperatureIssue="Current GPU temperature unavailable (NVIDIA status "+code+").";
        return result;
    }
    static IntPtr Handle(string uuid){
        if(String.IsNullOrEmpty(uuid) || !System.Text.RegularExpressions.Regex.IsMatch(uuid,@"\AGPU-[a-fA-F0-9-]+\z"))throw new ArgumentException("Invalid GPU identity.");
        IntPtr device;Check(byId(uuid,out device),"Find selected GPU");
        if(!String.Equals(Text(device,uuidText),uuid,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("GPU identity mismatch.");return device;
    }
    public static PCNvidiaClockDevice[] ReadAll(){lock(gate){Initialize();uint total;Check(count(out total),"Count NVIDIA GPUs");if(total>64)throw new InvalidOperationException("Unexpected GPU count.");var results=new List<PCNvidiaClockDevice>();for(uint i=0;i<total;i++){IntPtr d;Check(byIndex(i,out d),"Find NVIDIA GPU");results.Add(ReadHandle(d));}return results.ToArray();}}
    public static PCNvidiaClockDevice Read(string uuid){lock(gate){Initialize();return ReadHandle(Handle(uuid));}}
    public static void Write(string uuid,uint domain,int mhz){lock(gate){
        if(domain!=0 && domain!=2)throw new ArgumentException("Only graphics and memory offsets are supported.");
        Initialize();IntPtr device=Handle(uuid);var current=ReadOffset(device,domain);
        if(mhz<current.MinMHz || mhz>current.MaxMHz)throw new ArgumentOutOfRangeException("mhz","Offset is outside the driver-reported range.");
        // Only version, clock type, P0 and offset are input fields for the setter.
        var request=PCNvmlClockOffset.Create(domain);request.OffsetMHz=mhz;Check(setClock(device,ref request),"Set clock offset");
    }}
}
