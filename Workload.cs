using System;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Threading;

// Worker lifetime is bounded independently of WMI/UI responsiveness.
public sealed class PCInsightWorkload {
    private Thread[] threads;
    private long completed;
    private int remaining;
    private volatile bool cancelled;
    private Stopwatch timer;
    private double limit;
    private string error;
    public string Error { get { return error; } }
    public long CompletedMiB { get { return Interlocked.Read(ref completed); } }
    public double Seconds { get { return timer == null ? 0 : timer.Elapsed.TotalSeconds; } }
    public bool Done { get { if (threads == null) return true; foreach (Thread t in threads) if (t.IsAlive) return false; return true; } }
    public void Start(int count, double seconds) {
        if (threads != null) throw new InvalidOperationException("Workload already started.");
        if (count < 1 || count > 16 || seconds <= 0 || seconds > 60) throw new ArgumentOutOfRangeException();
        limit = seconds;
        remaining = count;
        threads = new Thread[count];
        timer = Stopwatch.StartNew();
        for (int i = 0; i < count; ++i) {
            threads[i] = new Thread(Run);
            threads[i].IsBackground = true;
            threads[i].Priority = ThreadPriority.BelowNormal;
            threads[i].Start();
        }
    }
    private void Run() {
        try {
            byte[] data = new byte[1048576];
            new Random(42).NextBytes(data);
            using (SHA256 hash = SHA256.Create()) {
                while (!cancelled && timer.Elapsed.TotalSeconds < limit) {
                    hash.ComputeHash(data);
                    Interlocked.Increment(ref completed);
                }
            }
        } catch (Exception ex) { Interlocked.CompareExchange(ref error, ex.Message, null); cancelled = true; }
        finally { if (Interlocked.Decrement(ref remaining) == 0) timer.Stop(); }
    }
    public void Stop() {
        cancelled = true;
        if (threads != null) foreach (Thread t in threads) if (t != null) t.Join();
        if (timer != null) timer.Stop();
    }
}
