// fr_native.cs - native helpers of the full-EEG-rerun lab driver (compiled by fr_lib.ps1 with Add-Type, .NET Framework / C# 5).
//
// FrJob  : file-system operations on the mapped lab share (R:) run on a worker thread, so a stalled SMB read
//          can never freeze the driver (the driver polls Done / IdleSec and gives up on a stall; the abandoned
//          thread is a background thread and dies with the process).
// FrNet  : WNetAddConnection2 / WNetCancelConnection2 / WNetGetConnection - maps R: for THIS logon session with
//          the credential held in memory only (never on a command line, never in a log).
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Security.Cryptography;
using System.Runtime.InteropServices;

public class FrJob
{
    public volatile bool Done;
    public volatile bool Failed;
    public string Result = "";
    public string Error = "";
    public long Bytes;
    public long Total;
    public Thread Worker;
    long lastTicks;

    FrJob() { Touch(); }
    void Touch() { Interlocked.Exchange(ref lastTicks, DateTime.UtcNow.Ticks); }
    public double IdleSec { get { return (DateTime.UtcNow.Ticks - Interlocked.Read(ref lastTicks)) / 1e7; } }

    delegate void Body(FrJob j);

    static FrJob Start(Body b)
    {
        FrJob j = new FrJob();
        j.Worker = new Thread(delegate()
        {
            try { b(j); }
            catch (Exception e) { j.Error = e.GetType().Name + ": " + e.Message; j.Failed = true; }
            j.Done = true;
        });
        j.Worker.IsBackground = true;
        j.Worker.Start();
        return j;
    }

    static string Hex(byte[] h)
    {
        StringBuilder sb = new StringBuilder(h.Length * 2);
        for (int i = 0; i < h.Length; i++) sb.Append(h[i].ToString("x2"));
        return sb.ToString();
    }

    // Result = lowercase SHA-256 hex of the file
    public static FrJob Hash(string path)
    {
        return Start(delegate(FrJob j)
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 20))
            using (SHA256 sha = SHA256.Create())
            {
                j.Total = fs.Length;
                byte[] buf = new byte[4 << 20];
                int n;
                while ((n = fs.Read(buf, 0, buf.Length)) > 0)
                {
                    sha.TransformBlock(buf, 0, n, null, 0);
                    j.Bytes += n;
                    j.Touch();
                }
                sha.TransformFinalBlock(buf, 0, 0);
                j.Result = Hex(sha.Hash);
            }
        });
    }

    // copies src to dst (via dst + ".part", renamed at the end) and returns the SHA-256 of what was READ from src
    public static FrJob CopyHash(string src, string dst, bool overwrite)
    {
        return Start(delegate(FrJob j)
        {
            if (!overwrite && File.Exists(dst)) throw new IOException("destination exists: " + dst);
            string part = dst + ".part";
            using (FileStream fi = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 1 << 20))
            using (SHA256 sha = SHA256.Create())
            {
                j.Total = fi.Length;
                using (FileStream fo = new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20))
                {
                    byte[] buf = new byte[4 << 20];
                    int n;
                    while ((n = fi.Read(buf, 0, buf.Length)) > 0)
                    {
                        sha.TransformBlock(buf, 0, n, null, 0);
                        fo.Write(buf, 0, n);
                        j.Bytes += n;
                        j.Touch();
                    }
                    fo.Flush(true);
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                j.Result = Hex(sha.Hash);
            }
            if (File.Exists(dst)) File.Delete(dst);   // only reachable with overwrite = true, i.e. a backup on the local volume, never on R:
            File.Move(part, dst);
        });
    }

    // plain copy without hashing (used for the small sheet snapshots)
    public static FrJob Copy(string src, string dst)
    {
        return Start(delegate(FrJob j)
        {
            File.Copy(src, dst, true);
            j.Result = "ok";
        });
    }

    // Result = "1" if a file or a directory exists
    public static FrJob Exists(string path)
    {
        return Start(delegate(FrJob j) { j.Result = (File.Exists(path) || Directory.Exists(path)) ? "1" : "0"; });
    }

    // opens the file and reads its first bytes: proves the share answers and the credential is accepted
    public static FrJob Probe(string path)
    {
        return Start(delegate(FrJob j)
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                byte[] b = new byte[64];
                int n = fs.Read(b, 0, b.Length);
                j.Result = "ok:" + n;
            }
        });
    }

    // Result = "length|lastWriteUtcTicks" ; "missing" if there is no such file
    public static FrJob Info(string path)
    {
        return Start(delegate(FrJob j)
        {
            FileInfo fi = new FileInfo(path);
            if (!fi.Exists) { j.Result = "missing"; return; }
            j.Result = fi.Length.ToString() + "|" + fi.LastWriteTimeUtc.Ticks.ToString();
        });
    }

    // rename on the same volume; refuses to overwrite
    public static FrJob Move(string src, string dst)
    {
        return Start(delegate(FrJob j)
        {
            if (File.Exists(dst)) throw new IOException("destination exists: " + dst);
            File.Move(src, dst);
            j.Result = "ok";
        });
    }

    public static FrJob Mkdir(string dir)
    {
        return Start(delegate(FrJob j) { Directory.CreateDirectory(dir); j.Result = "ok"; });
    }

    // Result = free bytes available to the caller on the volume of path
    public static FrJob FreeSpace(string path)
    {
        return Start(delegate(FrJob j)
        {
            ulong free, total, totalFree;
            if (!FrNet.GetDiskFreeSpaceEx(path, out free, out total, out totalFree))
                throw new IOException("GetDiskFreeSpaceEx failed: " + Marshal.GetLastWin32Error());
            j.Result = free.ToString();
        });
    }
}

public static class FrNet
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NETRESOURCE
    {
        public int dwScope;
        public int dwType;
        public int dwDisplayType;
        public int dwUsage;
        public string lpLocalName;
        public string lpRemoteName;
        public string lpComment;
        public string lpProvider;
    }

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    static extern int WNetAddConnection2(ref NETRESOURCE lpNetResource, string lpPassword, string lpUsername, int dwFlags);

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    static extern int WNetCancelConnection2(string lpName, int dwFlags, bool fForce);

    [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
    static extern int WNetGetConnection(string lpLocalName, StringBuilder lpRemoteName, ref int lpnLength);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool GetDiskFreeSpaceEx(string lpDirectoryName, out ulong lpFreeBytesAvailable, out ulong lpTotalNumberOfBytes, out ulong lpTotalNumberOfFreeBytes);

    // 0 = ok. The password stays in this call; nothing is logged here.
    public static int Add(string localName, string remoteName, string user, string password)
    {
        NETRESOURCE nr = new NETRESOURCE();
        nr.dwType = 1;                 // RESOURCETYPE_DISK
        nr.lpLocalName = localName;    // "R:"
        nr.lpRemoteName = remoteName;
        nr.lpProvider = null;
        return WNetAddConnection2(ref nr, password, user, 0);   // flags 0: this logon session only, not remembered
    }

    public static int Cancel(string name)
    {
        return WNetCancelConnection2(name, 0, true);
    }

    // "" if the letter is not mapped in this logon session, else the remote name
    public static string Remote(string localName)
    {
        StringBuilder sb = new StringBuilder(1024);
        int n = sb.Capacity;
        int rc = WNetGetConnection(localName, sb, ref n);
        return rc == 0 ? sb.ToString() : "";
    }
}

// A Windows job object with KILL_ON_JOB_CLOSE: every MATLAB the driver starts is assigned to it, so when the driver dies - even
// killed hard - the operating system kills the MATLAB tree with it (a restarted driver never meets an orphaned MATLAB that is
// still writing a final).  The lock holder is deliberately NOT put in it: it releases the sheet lock cleanly when its parent dies.
public static class FrKillJob
{
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cbInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    static IntPtr job = IntPtr.Zero;

    public static bool Create()
    {
        if (job != IntPtr.Zero) return true;
        IntPtr h = CreateJobObject(IntPtr.Zero, null);
        if (h == IntPtr.Zero) return false;
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = 0x2000;      // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(len);
        try
        {
            Marshal.StructureToPtr(info, p, false);
            if (!SetInformationJobObject(h, 9, p, (uint)len)) return false;   // 9 = JobObjectExtendedLimitInformation
        }
        finally { Marshal.FreeHGlobal(p); }
        job = h;
        return true;
    }

    // returns the Win32 error code (0 = assigned)
    public static int Assign(IntPtr processHandle)
    {
        if (job == IntPtr.Zero && !Create()) return Marshal.GetLastWin32Error();
        return AssignProcessToJobObject(job, processHandle) ? 0 : Marshal.GetLastWin32Error();
    }
}
