using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

// Fixed offscreen 1280x720, 256-iteration fragment workload. No screen presentation or VSync.
public sealed class PCInsightGpuWorkload {
 private Thread thread; private volatile bool cancelled, begin, ready; private string error, renderer;
 private volatile string phase="Preparing";
 public string Phase { get { return phase; } }
 private long frames; private Stopwatch timer; private double duration;
 public string Error { get { return error; } } public string Renderer { get { return renderer; } }
 public bool Ready { get { return ready; } } public bool Done { get { return thread != null && !thread.IsAlive; } }
 public long Frames { get { return Interlocked.Read(ref frames); } }
 public double Seconds { get { return timer == null ? 0 : timer.Elapsed.TotalSeconds; } }
 private bool monitored; private long heartbeat;
 public void KeepAlive() { Interlocked.Exchange(ref heartbeat,Stopwatch.GetTimestamp()); }
 private void CheckHeartbeat() { if(monitored && (Stopwatch.GetTimestamp()-Interlocked.Read(ref heartbeat))/(double)Stopwatch.Frequency>6) throw new TimeoutException("Sensor heartbeat expired; GPU load stopped."); }
 private void PrepareCore(double seconds) { duration=seconds; KeepAlive(); thread=new Thread(Run); thread.IsBackground=true; thread.Start(); }
 public void Prepare(double seconds) { if(thread!=null || Double.IsNaN(seconds) || Double.IsInfinity(seconds) || seconds<=0 || seconds>30) throw new ArgumentOutOfRangeException(); PrepareCore(seconds); }
 public void PrepareMonitored(int seconds) { if(thread!=null || (seconds!=300 && seconds!=600)) throw new ArgumentOutOfRangeException(); monitored=true; PrepareCore(seconds); }
 public void Begin() { KeepAlive(); begin=true; }
 public void Stop() { cancelled=true; if(thread!=null && !thread.Join(3000)) throw new TimeoutException("GPU driver did not respond to stop."); }
 [StructLayout(LayoutKind.Sequential)] struct PFD { public ushort size,version; public uint flags; public byte pixel,color,red,redShift,green,greenShift,blue,blueShift,alpha,alphaShift,accum,accumR,accumG,accumB,accumA,depth,stencil,aux,layer,reserved; public uint layerMask,visible,damage; }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
 [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr w);
 [DllImport("gdi32.dll")] static extern int ChoosePixelFormat(IntPtr dc,ref PFD p);
 [DllImport("gdi32.dll")] static extern bool SetPixelFormat(IntPtr dc,int format,ref PFD p);
 [DllImport("opengl32.dll")] static extern IntPtr wglCreateContext(IntPtr dc);
 [DllImport("opengl32.dll")] static extern bool wglMakeCurrent(IntPtr dc,IntPtr ctx);
 [DllImport("opengl32.dll")] static extern bool wglDeleteContext(IntPtr ctx);
 [DllImport("opengl32.dll",CharSet=CharSet.Ansi)] static extern IntPtr wglGetProcAddress(string name);
 [DllImport("opengl32.dll")] static extern IntPtr glGetString(uint name);
 [DllImport("opengl32.dll")] static extern void glViewport(int x,int y,int w,int h);
 [DllImport("opengl32.dll")] static extern void glGenTextures(int count,out uint texture);
 [DllImport("opengl32.dll")] static extern void glBindTexture(uint target,uint texture);
 [DllImport("opengl32.dll")] static extern void glTexParameteri(uint target,uint name,int value);
 [DllImport("opengl32.dll")] static extern void glTexImage2D(uint target,int level,int format,int w,int h,int border,uint external,uint type,IntPtr data);
 [DllImport("opengl32.dll")] static extern void glBegin(uint mode);
 [DllImport("opengl32.dll")] static extern void glVertex2f(float x,float y);
 [DllImport("opengl32.dll")] static extern void glEnd();
 [DllImport("opengl32.dll")] static extern void glFinish();
 [DllImport("opengl32.dll")] static extern uint glGetError();
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint CreateShader(uint type);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void ShaderSource(uint shader,int count,IntPtr strings,IntPtr lengths);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void One(uint id);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Status(uint id,uint name,out int value);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint CreateProgram();
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Two(uint a,uint b);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Generate(int n,out uint value);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate void Attach(uint target,uint attachment,uint textureTarget,uint texture,int level);
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint Check(uint target);
 static T Load<T>(string name) where T:class { IntPtr p=wglGetProcAddress(name); long n=p.ToInt64(); if(n==0 || n==1 || n==2 || n==3 || n==-1) throw new NotSupportedException("GPU does not expose "+name); return Marshal.GetDelegateForFunctionPointer(p,typeof(T)) as T; }
 static uint Compile(uint type,string text) {
  uint shader=Load<CreateShader>("glCreateShader")(type); IntPtr str=Marshal.StringToHGlobalAnsi(text), array=Marshal.AllocHGlobal(IntPtr.Size);
  try { Marshal.WriteIntPtr(array,str); Load<ShaderSource>("glShaderSource")(shader,1,array,IntPtr.Zero); Load<One>("glCompileShader")(shader); int status; Load<Status>("glGetShaderiv")(shader,0x8B81,out status); if(status==0) throw new NotSupportedException("GPU shader compilation failed."); return shader; }
  finally { Marshal.FreeHGlobal(array); Marshal.FreeHGlobal(str); }
 }
 static void Draw() { glBegin(0x0007); glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd(); }
 static void DrawBatch() { for(int i=0;i<8;i++) Draw(); glFinish(); if(glGetError()!=0) throw new InvalidOperationException("GPU rendering failed."); }
 private void Run() {
  IntPtr window=IntPtr.Zero,dc=IntPtr.Zero,ctx=IntPtr.Zero;
  try {
   window=CreateWindowEx(0,"STATIC","PC Insight offscreen GPU test",0x80000000,0,0,1280,720,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
   if(window==IntPtr.Zero) throw new InvalidOperationException("Cannot create GPU context window."); dc=GetDC(window);
   PFD p=new PFD();p.size=(ushort)Marshal.SizeOf(typeof(PFD));p.version=1;p.flags=0x24;p.color=32;
   int fmt=ChoosePixelFormat(dc,ref p);if(fmt==0 || !SetPixelFormat(dc,fmt,ref p)) throw new NotSupportedException("OpenGL pixel format unavailable.");
   ctx=wglCreateContext(dc);if(ctx==IntPtr.Zero || !wglMakeCurrent(dc,ctx)) throw new NotSupportedException("OpenGL context unavailable.");
   renderer=Marshal.PtrToStringAnsi(glGetString(0x1F01));
   if(String.IsNullOrEmpty(renderer) || renderer.IndexOf("GDI",StringComparison.OrdinalIgnoreCase)>=0 || renderer.IndexOf("llvmpipe",StringComparison.OrdinalIgnoreCase)>=0 || renderer.IndexOf("software",StringComparison.OrdinalIgnoreCase)>=0) throw new NotSupportedException("Hardware OpenGL renderer unavailable.");
   uint vs=Compile(0x8B31,"#version 120\nvoid main(){gl_Position=gl_Vertex;}");
   uint fs=Compile(0x8B30,"#version 120\nvoid main(){vec2 p=gl_FragCoord.xy/vec2(1280.0,720.0);vec3 v=vec3(p,0.37);for(int i=0;i<256;i++){v=fract(sin(v.yzx*1.13+vec3(0.17,0.31,0.53))*2.17);}gl_FragColor=vec4(v,1.0);}");
   uint program=Load<CreateProgram>("glCreateProgram")();Two attach=Load<Two>("glAttachShader");attach(program,vs);attach(program,fs);Load<One>("glLinkProgram")(program);int linked;Load<Status>("glGetProgramiv")(program,0x8B82,out linked);if(linked==0) throw new NotSupportedException("GPU program linking failed.");Load<One>("glUseProgram")(program);
   uint texture;glGenTextures(1,out texture);glBindTexture(0x0DE1,texture);glTexParameteri(0x0DE1,0x2801,0x2600);glTexParameteri(0x0DE1,0x2800,0x2600);glTexImage2D(0x0DE1,0,0x8058,1280,720,0,0x1908,0x1401,IntPtr.Zero);
   uint fbo;Load<Generate>("glGenFramebuffers")(1,out fbo);Load<Two>("glBindFramebuffer")(0x8D40,fbo);Load<Attach>("glFramebufferTexture2D")(0x8D40,0x8CE0,0x0DE1,texture,0);if(Load<Check>("glCheckFramebufferStatus")(0x8D40)!=0x8CD5) throw new NotSupportedException("Offscreen framebuffer unavailable.");glViewport(0,0,1280,720);
   ready=true;var wait=Stopwatch.StartNew();while(!begin && !cancelled && wait.Elapsed.TotalSeconds<30) Thread.Sleep(20);
   if(!begin || cancelled) return;
   phase="Warm-up (unscored)";
   var warmup=Stopwatch.StartNew();while(!cancelled && warmup.Elapsed.TotalSeconds<5) { CheckHeartbeat(); DrawBatch(); }
   if(cancelled) return;
   phase="Measuring";
   timer=Stopwatch.StartNew();while(!cancelled && timer.Elapsed.TotalSeconds<duration) { CheckHeartbeat(); DrawBatch();Interlocked.Add(ref frames,8); }timer.Stop();phase="Finished";
  } catch(Exception ex) { error=ex.Message; }
  finally { if(timer!=null)timer.Stop();if(ctx!=IntPtr.Zero){wglMakeCurrent(IntPtr.Zero,IntPtr.Zero);wglDeleteContext(ctx);}if(dc!=IntPtr.Zero)ReleaseDC(window,dc);if(window!=IntPtr.Zero)DestroyWindow(window); }
 }
}
