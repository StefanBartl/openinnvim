// Pipes.cs - the pipe namespace: enumeration, name parsing, connecting, and the trust check.
//
// The pipe namespace is global on the machine and any local process can create any free name.
// So a name proves nothing: after connecting, and before a single byte is written, the process
// that serves the pipe is identified and checked (Trust). A squatted name never receives a path.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace OpenInNvim
{
    /// <summary>One byte stream to a Neovim instance (pipe or TCP), with a time limit on every wait.</summary>
    public interface IChannel : IDisposable
    {
        /// <summary>
        /// Read into <paramref name="buffer"/> at <paramref name="offset"/>; the caller guarantees
        /// ChannelRead.ChunkSize free bytes there. Returns the byte count, or one of the ChannelRead values.
        /// </summary>
        int Read(byte[] buffer, int offset, int timeoutMs);

        bool Write(byte[] data, int count, int timeoutMs);
    }

    public static class ChannelRead
    {
        public const int ChunkSize = 16384;
        public const int Closed = 0;
        public const int TimedOut = -1;
        public const int Failed = -2;
    }

    public sealed class PipeConnectResult
    {
        /// <summary>Non-null only when the server passed the trust check; the caller owns it.</summary>
        public PipeChannel Channel;
        /// <summary>No pipe of that name exists (as opposed to: it exists but is not used).</summary>
        public bool NotFound;
        public int ServerPid;
        public long ServerCreated;
        /// <summary>Why the pipe is not used (null when Channel is set).</summary>
        public string Reason;
    }

    public static class Pipes
    {
        public const string Prefix = @"\\.\pipe\";

        /// <summary>
        /// Names of all pipes (without the \\.\pipe\ prefix). FindFirstFileW instead of Directory.GetFiles:
        /// the latter throws on names with characters that are illegal in paths, and any process can
        /// create such a name.
        /// </summary>
        public static List<string> List()
        {
            List<string> names = new List<string>(512);
            IntPtr data = Marshal.AllocHGlobal(Native.FindDataSize);
            try
            {
                IntPtr h = Native.FindFirstFileW(Prefix + "*", data);
                if (h == Native.InvalidHandle) { return names; }
                try
                {
                    do
                    {
                        string name = Marshal.PtrToStringUni(IntPtr.Add(data, Native.FindDataNameOffset));
                        if (!string.IsNullOrEmpty(name)) { names.Add(name); }
                    }
                    while (Native.FindNextFileW(h, data));
                }
                finally { Native.FindClose(h); }
            }
            finally { Marshal.FreeHGlobal(data); }
            return names;
        }

        /// <summary>
        /// Parse "nvim.&lt;pid&gt;.&lt;n&gt;" by hand. The name is untrusted text: digits only, and both numbers
        /// must fit an int (a pipe "nvim.99999999999.0" is simply not a Neovim pipe).
        /// </summary>
        public static bool TryParseDefault(string name, out int pid, out int index)
        {
            pid = 0;
            index = 0;
            if (name == null || name.Length < 8 || string.CompareOrdinal(name, 0, "nvim.", 0, 5) != 0) { return false; }
            int dot = name.IndexOf('.', 5);
            if (dot < 6 || dot == name.Length - 1) { return false; }
            if (!int.TryParse(name.Substring(5, dot - 5), NumberStyles.None, CultureInfo.InvariantCulture, out pid)) { return false; }
            if (!int.TryParse(name.Substring(dot + 1), NumberStyles.None, CultureInfo.InvariantCulture, out index)) { return false; }
            return pid > 0;
        }

        /// <summary>True for a full local pipe name (\\.\pipe\x).</summary>
        public static bool IsPipeAddress(string address)
        {
            return address != null && address.Length > Prefix.Length
                && address.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Connect to a pipe and verify who serves it. <paramref name="expectedPid"/> is the PID a
        /// "nvim.&lt;pid&gt;.&lt;n&gt;" name claims (0: the name makes no claim). <paramref name="onlyPids"/>, when not null,
        /// is the OPEN_IN_NVIM_ONLY_PIDS list: a server outside it is never written to.
        /// </summary>
        public static PipeConnectResult ConnectTrusted(string fullName, int expectedPid, int[] onlyPids, int timeoutMs)
        {
            PipeConnectResult res = new PipeConnectResult();
            int error;
            IntPtr handle = Open(fullName, timeoutMs, out error);
            if (handle == Native.InvalidHandle)
            {
                res.NotFound = (error == Native.ERROR_FILE_NOT_FOUND);
                res.Reason = res.NotFound ? "no such pipe" : ("cannot connect (error " + error.ToString(CultureInfo.InvariantCulture) + ")");
                return res;
            }

            uint serverPid;
            if (!Native.GetNamedPipeServerProcessId(handle, out serverPid) || serverPid == 0)
            {
                res.Reason = "the pipe's server process is unknown";
            }
            else
            {
                res.ServerPid = (int)serverPid;
                if (expectedPid != 0 && expectedPid != res.ServerPid)
                {
                    res.Reason = "served by pid " + res.ServerPid.ToString(CultureInfo.InvariantCulture) + ", not by the pid in its name";
                }
                else if (onlyPids != null && Array.IndexOf(onlyPids, res.ServerPid) < 0)
                {
                    res.Reason = "pid " + res.ServerPid.ToString(CultureInfo.InvariantCulture) + " is not in OPEN_IN_NVIM_ONLY_PIDS";
                }
                else
                {
                    res.Reason = Trust.CheckProcess(res.ServerPid, out res.ServerCreated);
                }
            }

            if (res.Reason != null)
            {
                Native.CloseHandle(handle);
                return res;
            }
            res.Channel = new PipeChannel(handle);
            return res;
        }

        private static IntPtr Open(string fullName, int timeoutMs, out int error)
        {
            long deadline = Clock.Ms + timeoutMs;
            for (;;)
            {
                // CreateFileW directly: a missing pipe fails at once (NamedPipeClientStream.Connect spins
                // until its timeout), and no path normalisation touches the name.
                IntPtr h = Native.CreateFileW(fullName, Native.GENERIC_READ | Native.GENERIC_WRITE, 0, IntPtr.Zero,
                    Native.OPEN_EXISTING, Native.FILE_FLAG_OVERLAPPED | Native.SECURITY_SQOS_PRESENT, IntPtr.Zero);
                if (h != Native.InvalidHandle) { error = 0; return h; }
                error = Marshal.GetLastWin32Error();
                if (error != Native.ERROR_PIPE_BUSY) { return Native.InvalidHandle; }
                long left = deadline - Clock.Ms;
                if (left <= 0) { return Native.InvalidHandle; }
                Native.WaitNamedPipeW(fullName, (uint)(left < 50 ? left : 50));
            }
        }
    }

    /// <summary>Who is the process behind a pipe: the four conditions of the design's trust section.</summary>
    public static class Trust
    {
        private static IntPtr ownSid = IntPtr.Zero;
        private static bool ownSidRead;
        private static uint ownSession;
        private static bool ownSessionRead;

        /// <summary>
        /// Null when the process is a Neovim of this user in this logon session, otherwise the reason.
        /// <paramref name="created"/> receives its creation time (FILETIME ticks) for ordering.
        /// </summary>
        public static string CheckProcess(int pid, out long created)
        {
            created = 0;
            IntPtr process = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
            if (process == IntPtr.Zero) { return "process " + pid.ToString(CultureInfo.InvariantCulture) + " cannot be opened"; }
            try
            {
                StringBuilder image = new StringBuilder(1024);
                int size = image.Capacity;
                if (!Native.QueryFullProcessImageNameW(process, 0, image, ref size)) { return "process image unknown"; }
                string path = image.ToString();
                int slash = path.LastIndexOf('\\');
                string file = slash >= 0 ? path.Substring(slash + 1) : path;
                if (!string.Equals(file, "nvim.exe", StringComparison.OrdinalIgnoreCase)) { return "served by " + file + ", not by nvim.exe"; }

                uint session;
                if (!Native.ProcessIdToSessionId((uint)pid, out session) || session != OwnSession()) { return "another logon session"; }

                // A token that cannot be read is not trusted: "probably mine" is not good enough.
                if (!SameUser(process)) { return "another user (or its token cannot be read)"; }

                long exit, kernel, user;
                Native.GetProcessTimes(process, out created, out exit, out kernel, out user);
                return null;
            }
            finally { Native.CloseHandle(process); }
        }

        private static uint OwnSession()
        {
            if (!ownSessionRead)
            {
                if (!Native.ProcessIdToSessionId(Native.GetCurrentProcessId(), out ownSession)) { ownSession = uint.MaxValue; }
                ownSessionRead = true;
            }
            return ownSession;
        }

        private static bool SameUser(IntPtr process)
        {
            if (!ownSidRead)
            {
                // Kept for the life of the process; the TOKEN_USER block holds the SID it points to.
                ownSid = ReadTokenUser(Native.GetCurrentProcess());
                ownSidRead = true;
            }
            if (ownSid == IntPtr.Zero) { return false; }
            IntPtr other = ReadTokenUser(process);
            if (other == IntPtr.Zero) { return false; }
            try { return Native.EqualSid(Marshal.ReadIntPtr(ownSid), Marshal.ReadIntPtr(other)); }
            finally { Marshal.FreeHGlobal(other); }
        }

        /// <summary>The TOKEN_USER block of a process (its first field is the SID pointer), or Zero.</summary>
        private static IntPtr ReadTokenUser(IntPtr process)
        {
            IntPtr token;
            if (!Native.OpenProcessToken(process, Native.TOKEN_QUERY, out token)) { return IntPtr.Zero; }
            try
            {
                const int Size = 256;   // a SID is at most 68 bytes
                IntPtr block = Marshal.AllocHGlobal(Size);
                int needed;
                if (!Native.GetTokenInformation(token, Native.TokenUser, block, Size, out needed))
                {
                    Marshal.FreeHGlobal(block);
                    return IntPtr.Zero;
                }
                return block;
            }
            finally { Native.CloseHandle(token); }
        }
    }

    /// <summary>
    /// Overlapped I/O on a pipe handle. A read that ran into its time limit stays pending and is picked
    /// up by the next Read: cancelling it could lose bytes that arrive in the same instant.
    /// </summary>
    public sealed class PipeChannel : IChannel
    {
        private IntPtr handle;
        private IntPtr readEvent;
        private IntPtr writeEvent;
        private IntPtr readOverlapped;
        private IntPtr writeOverlapped;
        private IntPtr readBuffer;
        private bool readPending;

        internal PipeChannel(IntPtr pipeHandle)
        {
            handle = pipeHandle;
            readEvent = Native.CreateEventW(IntPtr.Zero, true, false, IntPtr.Zero);
            writeEvent = Native.CreateEventW(IntPtr.Zero, true, false, IntPtr.Zero);
            readOverlapped = NewOverlapped(readEvent);
            writeOverlapped = NewOverlapped(writeEvent);
            readBuffer = Marshal.AllocHGlobal(ChannelRead.ChunkSize);
        }

        // OVERLAPPED: Internal, InternalHigh (pointer sized), Offset, OffsetHigh (4 bytes each), hEvent.
        private static IntPtr NewOverlapped(IntPtr ev)
        {
            int size = IntPtr.Size * 3 + 8;
            IntPtr mem = Marshal.AllocHGlobal(size);
            for (int i = 0; i < size; i++) { Marshal.WriteByte(mem, i, 0); }
            Marshal.WriteIntPtr(mem, IntPtr.Size * 2 + 8, ev);
            return mem;
        }

        public int Read(byte[] buffer, int offset, int timeoutMs)
        {
            if (handle == Native.InvalidHandle) { return ChannelRead.Failed; }
            if (!readPending)
            {
                if (!Native.ReadFile(handle, readBuffer, ChannelRead.ChunkSize, IntPtr.Zero, readOverlapped))
                {
                    int err = Marshal.GetLastWin32Error();
                    if (err == Native.ERROR_IO_PENDING) { readPending = true; }
                    else if (IsEndOfPipe(err)) { return ChannelRead.Closed; }
                    else if (err != Native.ERROR_MORE_DATA) { return ChannelRead.Failed; }
                }
            }
            if (readPending)
            {
                uint w = Native.WaitForSingleObject(readEvent, timeoutMs > 0 ? (uint)timeoutMs : 0);
                if (w == Native.WAIT_TIMEOUT) { return ChannelRead.TimedOut; }
                if (w != Native.WAIT_OBJECT_0) { return ChannelRead.Failed; }
                readPending = false;
            }
            int n;
            if (!Native.GetOverlappedResult(handle, readOverlapped, out n, false))
            {
                int err = Marshal.GetLastWin32Error();
                if (IsEndOfPipe(err)) { return ChannelRead.Closed; }
                if (err != Native.ERROR_MORE_DATA) { return ChannelRead.Failed; }
            }
            if (n <= 0) { return ChannelRead.Closed; }
            Marshal.Copy(readBuffer, buffer, offset, n);
            return n;
        }

        private static bool IsEndOfPipe(int err)
        {
            return err == Native.ERROR_BROKEN_PIPE || err == Native.ERROR_PIPE_NOT_CONNECTED
                || err == Native.ERROR_HANDLE_EOF || err == Native.ERROR_NO_DATA;
        }

        public bool Write(byte[] data, int count, int timeoutMs)
        {
            if (handle == Native.InvalidHandle) { return false; }
            IntPtr mem = Marshal.AllocHGlobal(count);
            try
            {
                Marshal.Copy(data, 0, mem, count);
                long deadline = Clock.Ms + timeoutMs;
                int done = 0;
                while (done < count)
                {
                    if (!Native.WriteFile(handle, IntPtr.Add(mem, done), count - done, IntPtr.Zero, writeOverlapped))
                    {
                        if (Marshal.GetLastWin32Error() != Native.ERROR_IO_PENDING) { return false; }
                        long left = deadline - Clock.Ms;
                        uint w = Native.WaitForSingleObject(writeEvent, left > 0 ? (uint)left : 0);
                        if (w != Native.WAIT_OBJECT_0)
                        {
                            // The kernel still owns "mem" until the write is really gone.
                            int ignored;
                            Native.CancelIoEx(handle, writeOverlapped);
                            Native.GetOverlappedResult(handle, writeOverlapped, out ignored, true);
                            return false;
                        }
                    }
                    int n;
                    if (!Native.GetOverlappedResult(handle, writeOverlapped, out n, false) || n <= 0) { return false; }
                    done += n;
                }
                return true;
            }
            finally { Marshal.FreeHGlobal(mem); }
        }

        public void Dispose()
        {
            if (handle == Native.InvalidHandle) { return; }
            if (readPending)
            {
                // Same reason as in Write: the pending read still points at readBuffer.
                int ignored;
                Native.CancelIoEx(handle, readOverlapped);
                Native.GetOverlappedResult(handle, readOverlapped, out ignored, true);
                readPending = false;
            }
            Native.CloseHandle(handle);
            handle = Native.InvalidHandle;
            Native.CloseHandle(readEvent);
            Native.CloseHandle(writeEvent);
            Marshal.FreeHGlobal(readOverlapped);
            Marshal.FreeHGlobal(writeOverlapped);
            Marshal.FreeHGlobal(readBuffer);
        }
    }
}
