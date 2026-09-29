using System;
using System.Diagnostics;
using System.Threading;
public sealed class PCInsightMemoryWorkload {
 private Thread thread;private volatile bool cancelled;private Stopwatch timer;private long copied;private string error;
 public string Error { get { return error; } } public bool Done { get { return thread!=null && !thread.IsAlive; } }
 public long CompletedMiB { get { return Interlocked.Read(ref copied); } }
 public double Seconds { get { return timer==null ? 0 : timer.Elapsed.TotalSeconds; } }
 public void Start() { if(thread!=null)throw new InvalidOperationException();thread=new Thread(Run);thread.IsBackground=true;thread.Priority=ThreadPriority.BelowNormal;thread.Start(); }
 private void Run() { try { byte[] source=new byte[128*1048576],dest=new byte[source.Length];for(int i=0;i<source.Length;i++)source[i]=(byte)(i*31+17);Buffer.BlockCopy(source,0,dest,0,source.Length);
  timer=Stopwatch.StartNew();while(!cancelled && timer.Elapsed.TotalSeconds<20){Buffer.BlockCopy(source,0,dest,0,source.Length);Interlocked.Add(ref copied,128);}timer.Stop();
  for(int i=0;i<source.Length;i+=4096)if(source[i]!=dest[i])throw new InvalidOperationException("Sampled buffer verification failed.");
 } catch(Exception ex){error=ex.Message;} finally {if(timer!=null)timer.Stop();} }
 public void Stop(){cancelled=true;if(thread!=null)thread.Join();if(timer!=null)timer.Stop();}
}
