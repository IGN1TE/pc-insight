using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

public static class PCInsightOverlayNative {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetLong64(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW", SetLastError=true)] static extern IntPtr SetLong64(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetLong32(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)] static extern int SetLong32(IntPtr window, int index, int value);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    public static void MakePassive(IntPtr window) {
        // Match WPF's per-pixel transparency and pass mouse input through without activation.
        long style=IntPtr.Size==8 ? GetLong64(window,-20).ToInt64() : GetLong32(window,-20);
        style |= 0x80000L | 0x20L | 0x80L | 0x08000000L; // LAYERED | TRANSPARENT | TOOLWINDOW | NOACTIVATE
        if(IntPtr.Size==8) SetLong64(window,-20,new IntPtr(style)); else SetLong32(window,-20,(int)style);
        long actual=IntPtr.Size==8 ? GetLong64(window,-20).ToInt64() : GetLong32(window,-20);
        const long required=0x080800A0L; // Also require the layered window set by WPF.
        if((actual & required)!=required)throw new InvalidOperationException("Windows could not make the overlay click-through and non-activating.");
    }
}

// Handle WPF's ref Boolean in managed code. A PowerShell script-block delegate
// receives a Boolean value, not a PSReference with a writable Value property.
public sealed class PCInsightOverlayHotkey {
    readonly int hotkeyId;
    readonly Action pressed;
    public PCInsightOverlayHotkey(int id,Action callback){
        if(callback==null)throw new ArgumentNullException("callback");
        hotkeyId=id;pressed=callback;
    }
    public IntPtr HandleMessage(IntPtr window,int message,IntPtr wparam,IntPtr lparam,ref bool handled){
        if(message==0x0312 && wparam.ToInt64()==hotkeyId){
            handled=true;
            pressed();
        }
        return IntPtr.Zero;
    }
}

public sealed class PCInsightFpsReading {
    public double? Fps;
    public string Status;
    public PCInsightFpsReading(double? fps,string status){Fps=fps;Status=status;}
}

public sealed class PCInsightFpsDiagnostics {
    public uint TargetProcessId;
    public string CaptureMode="Standard tracking";
    public double ElapsedSeconds;
    public bool ProcessExited;
    public int? ExitCode;
    public long OutputLines,DataRows,AcceptedFrames,RejectedRows,OtherProcessRows;
    public bool HeaderSeen,ColumnsSupported;
    public string Header="",FirstOutputLine="",ErrorOutput="";
}

// CSV parsing and a bounded rolling window run on the pipe reader, never in a PowerShell callback.
public sealed class PCInsightFpsWindow {
    sealed class Sample { public double Time; public long Received; public Sample(double t,long r){Time=t;Received=r;} }
    readonly object gate=new object();
    readonly uint target;
    readonly Dictionary<string,Queue<Sample>> chains=new Dictionary<string,Queue<Sample>>();
    int pidIndex=-1,chainIndex=-1,timeIndex=-1;
    long outputLines,dataRows,acceptedFrames,rejectedRows,otherProcessRows;
    bool headerSeen;
    string header="",firstOutputLine="";
    public PCInsightFpsWindow(uint processId){target=processId;}
    static string[] Csv(string line) {
        var fields=new List<string>();var value=new StringBuilder();bool quoted=false;
        for(int i=0;i<line.Length;i++){
            char c=line[i];
            if(c=='"') { if(quoted && i+1<line.Length && line[i+1]=='"'){value.Append('"');i++;}else quoted=!quoted; }
            else if(c==',' && !quoted){fields.Add(value.ToString());value.Length=0;}
            else value.Append(c);
        }
        if(quoted)return null;
        fields.Add(value.ToString());return fields.ToArray();
    }
    public void AddLine(string line,long receivedMilliseconds) {
        if(String.IsNullOrEmpty(line) || line.Length>8192)return;
        var fields=Csv(line);
        lock(gate){
            outputLines++;
            if(firstOutputLine.Length==0)firstOutputLine=line.Length>512 ? line.Substring(0,512) : line;
            if(fields==null){rejectedRows++;return;}
            if(Array.IndexOf(fields,"ProcessID")>=0){
                headerSeen=true;header=line.Length>1024 ? line.Substring(0,1024) : line;
                pidIndex=Array.IndexOf(fields,"ProcessID");chainIndex=Array.IndexOf(fields,"SwapChainAddress");timeIndex=Array.IndexOf(fields,"TimeInSeconds");
                chains.Clear();return;
            }
            int last=Math.Max(pidIndex,Math.Max(chainIndex,timeIndex));
            if(pidIndex<0 || chainIndex<0 || timeIndex<0)return;
            dataRows++;
            if(fields.Length<=last){rejectedRows++;return;}
            uint processId;double time;
            if(!UInt32.TryParse(fields[pidIndex],out processId)){rejectedRows++;return;}
            if(processId!=target){otherProcessRows++;return;}
            if(!Double.TryParse(fields[timeIndex],NumberStyles.Float,CultureInfo.InvariantCulture,out time) ||
               Double.IsNaN(time) || Double.IsInfinity(time) || time<0){rejectedRows++;return;}
            string key=fields[chainIndex];if(key.Length==0){rejectedRows++;return;}
            Queue<Sample> samples;
            if(!chains.TryGetValue(key,out samples)){
                // Expire abandoned chains before bounding unusual applications with many swap chains.
                var expired=new List<string>();
                foreach(var pair in chains){Sample newest=null;foreach(var s in pair.Value)newest=s;if(newest==null || receivedMilliseconds-newest.Received>2500)expired.Add(pair.Key);}
                foreach(string k in expired)chains.Remove(k);
                if(chains.Count>=32){rejectedRows++;return;}
                samples=new Queue<Sample>();chains.Add(key,samples);
            }
            Sample previous=null;foreach(var s in samples)previous=s;
            if(previous!=null && time<=previous.Time){rejectedRows++;return;}
            samples.Enqueue(new Sample(time,receivedMilliseconds));
            acceptedFrames++;
            while(samples.Count>2000 || (samples.Count>0 && time-samples.Peek().Time>2.0))samples.Dequeue();
        }
    }
    public PCInsightFpsReading Read(long nowMilliseconds) {
        lock(gate){
            int count=0;double? best=null;
            foreach(var samples in chains.Values){
                if(samples.Count<5)continue;
                Sample newest=null;foreach(var sample in samples)newest=sample;
                if(nowMilliseconds-newest.Received>2500 || nowMilliseconds<newest.Received)continue;
                double seconds=newest.Time-samples.Peek().Time;
                if(seconds>0 && samples.Count>count){count=samples.Count;best=(samples.Count-1)/seconds;}
            }
            string status="Waiting for game frames";
            if(best.HasValue)status="Application presentation FPS";
            else if(headerSeen && (pidIndex<0 || chainIndex<0 || timeIndex<0))status="FPS output format is not supported. Export FPS details.";
            else if(nowMilliseconds>=10000){
                if(outputLines==0)status="No frame data received for this app. Export FPS details.";
                else if(!headerSeen)status="FPS output has no recognized header. Export FPS details.";
                else if(acceptedFrames==0)status="Frame data arrived but could not be used for this app. Export FPS details.";
                else status="No recent FPS samples. Return to active gameplay or export FPS details.";
            }
            return new PCInsightFpsReading(best,status);
        }
    }
    public PCInsightFpsDiagnostics GetDiagnostics(){
        lock(gate){return new PCInsightFpsDiagnostics{
            TargetProcessId=target,OutputLines=outputLines,DataRows=dataRows,AcceptedFrames=acceptedFrames,
            RejectedRows=rejectedRows,OtherProcessRows=otherProcessRows,HeaderSeen=headerSeen,
            ColumnsSupported=pidIndex>=0 && chainIndex>=0 && timeIndex>=0,Header=header,FirstOutputLine=firstOutputLine
        };}
    }
}

public sealed class PCInsightFpsCapture : IDisposable {
    readonly Process process;
    readonly PCInsightFpsWindow samples;
    readonly Stopwatch clock=Stopwatch.StartNew();
    readonly string executable,session;
    readonly object errorGate=new object();
    readonly Queue<string> errors=new Queue<string>();
    bool disposed;
    public uint TargetProcessId {get;private set;}
    public static string CaptureArguments(uint targetProcessId,string sessionName){
        if(targetProcessId==0)throw new ArgumentOutOfRangeException("targetProcessId");
        // Session names are generated internally; keep command-line arguments unambiguous.
        if(String.IsNullOrEmpty(sessionName) || !System.Text.RegularExpressions.Regex.IsMatch(sessionName,@"\APCInsightOverlay-[0-9]+-[a-f0-9]{32}\z"))throw new ArgumentException("Invalid private capture session.");
        return "--process_id "+targetProcessId+" --session_name "+sessionName+
            " --output_stdout --no_console_stats --v1_metrics --no_track_input --terminate_on_proc_exit --timed 300 --terminate_after_timed";
    }
    public PCInsightFpsCapture(string path,uint targetProcessId) {
        executable=path;TargetProcessId=targetProcessId;samples=new PCInsightFpsWindow(targetProcessId);
        session="PCInsightOverlay-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N");
        process=new Process();
        // Five-minute sessions renew while visible and bound capture lifetime after an abrupt app crash.
        // Keep PresentMon's normal GPU/display event tracking for broader capture compatibility.
        process.StartInfo=new ProcessStartInfo(path,CaptureArguments(targetProcessId,session));
        process.StartInfo.UseShellExecute=false;process.StartInfo.CreateNoWindow=true;
        process.StartInfo.RedirectStandardOutput=true;process.StartInfo.RedirectStandardError=true;
        process.OutputDataReceived+=(sender,args)=>{if(args.Data!=null)samples.AddLine(args.Data,clock.ElapsedMilliseconds);};
        process.ErrorDataReceived+=(sender,args)=>{
            if(String.IsNullOrWhiteSpace(args.Data))return;
            lock(errorGate){errors.Enqueue(args.Data.Length>400 ? args.Data.Substring(0,400) : args.Data);while(errors.Count>8)errors.Dequeue();}
        };
        try{process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();}
        catch{process.Dispose();throw;}
    }
    public bool HasExited {get{return disposed || process.HasExited;}}
    public bool FinishedInterval {get{return !disposed && process.HasExited && process.ExitCode==0 && clock.Elapsed.TotalSeconds>=295;}}
    string ErrorOutput(){lock(errorGate){return String.Join(Environment.NewLine,errors.ToArray());}}
    public PCInsightFpsDiagnostics GetDiagnostics(){
        var result=samples.GetDiagnostics();result.ElapsedSeconds=clock.Elapsed.TotalSeconds;result.ErrorOutput=ErrorOutput();
        if(!disposed){result.ProcessExited=process.HasExited;if(result.ProcessExited)result.ExitCode=process.ExitCode;}
        return result;
    }
    public PCInsightFpsReading Read(){
        if(disposed)return new PCInsightFpsReading(null,"Capture stopped");
        if(process.HasExited){string error=ErrorOutput();return new PCInsightFpsReading(null,"FPS capture stopped (exit "+process.ExitCode+"). "+(error.Length>0 ? error : "Reopen PC Insight as administrator and try again."));}
        return samples.Read(clock.ElapsedMilliseconds);
    }
    public void Dispose(){
        if(disposed)return;disposed=true;
        try{
            // Only stop the private session this object created; never touch another tool's trace.
            var info=new ProcessStartInfo(executable,"--session_name "+session+" --terminate_existing_session");
            info.UseShellExecute=false;info.CreateNoWindow=true;
            using(var stop=Process.Start(info)){if(!stop.WaitForExit(1000)){stop.Kill();stop.WaitForExit(500);}}
        }catch{}
        try{if(!process.HasExited && !process.WaitForExit(500)){process.Kill();process.WaitForExit(500);}}catch{}
        process.Dispose();clock.Stop();
    }
}
