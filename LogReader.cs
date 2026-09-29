using System;
using System.IO;
using System.Text;

public static class PCInsightLogReader {
    // Read only headers and a bounded tail; never load a growing daily log in full.
    public static string[] Read(string path) {
        using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
            string ids, names;
            using (var reader = new StreamReader(file, Encoding.UTF8, true, 4096, true)) {
                ids = reader.ReadLine(); names = reader.ReadLine();
            }
            long size = file.Length;
            long start = Math.Max(0, size - 262144);
            file.Position = start;
            string tail;
            using (var reader = new StreamReader(file, Encoding.UTF8, true, 4096, true)) tail = reader.ReadToEnd();
            int end = tail.LastIndexOf('\n');
            if (end < 0) throw new InvalidDataException("No complete log row yet. Wait for logging to write a row.");
            tail = tail.Substring(0, end).TrimEnd('\r');
            int beginning = tail.LastIndexOf('\n');
            if (start > 0 && beginning < 0) throw new InvalidDataException("Log row exceeds supported size.");
            string row = tail.Substring(beginning + 1).TrimEnd('\r');
            return new string[] { ids, names, row };
        }
    }
}
