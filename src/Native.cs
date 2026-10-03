// Native.cs - the Win32 calls the launcher needs, and a monotonic clock.
//
// Everything on the click path goes through these few kernel32/advapi32 calls instead of
// System.Diagnostics.Process, System.IO.Pipes or System.Management: each of those loads another
// assembly and costs more than the whole job (see the measurements in the design document).

using System;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;

namespace OpenInNvim
{
    [SuppressUnmanagedCodeSecurity]
    internal static class Native
    {
        internal static readonly IntPtr InvalidHandle = new IntPtr(-1);

        internal const int ERROR_FILE_NOT_FOUND = 2;
        internal const int ERROR_HANDLE_EOF = 38;
        internal const int ERROR_BROKEN_PIPE = 109;
        internal const int ERROR_PIPE_BUSY = 231;
        internal const int ERROR_NO_DATA = 232;
        internal const int ERROR_PIPE_NOT_CONNECTED = 233;
        internal const int ERROR_MORE_DATA = 234;
        internal const int ERROR_IO_PENDING = 997;

        internal const uint GENERIC_READ = 0x80000000;
        internal const uint GENERIC_WRITE = 0x40000000;
        internal const uint OPEN_EXISTING = 3;
        internal const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        // SECURITY_ANONYMOUS is 0: with SQOS present and no level bits the server cannot impersonate us.
        internal const uint SECURITY_SQOS_PRESENT = 0x00100000;

        internal const uint WAIT_OBJECT_0 = 0;
        internal const uint WAIT_TIMEOUT = 0x102;

        internal const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        internal const uint TOKEN_QUERY = 0x0008;
        internal const int TokenUser = 1;

        // WIN32_FIND_DATAW: attributes (4) + three FILETIMEs (24) + size (8) + reserved (8), then
        // cFileName[260] and cAlternateFileName[14] as UTF-16.
        internal const int FindDataSize = 592;
        internal const int FindDataNameOffset = 44;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr FindFirstFileW(string lpFileName, IntPtr lpFindFileData);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool FindNextFileW(IntPtr hFindFile, IntPtr lpFindFileData);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool FindClose(IntPtr hFindFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
            IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WaitNamedPipeW(string lpNamedPipeName, uint nTimeOut);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ReadFile(IntPtr hFile, IntPtr lpBuffer, int nNumberOfBytesToRead,
            IntPtr lpNumberOfBytesRead, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WriteFile(IntPtr hFile, IntPtr lpBuffer, int nNumberOfBytesToWrite,
            IntPtr lpNumberOfBytesWritten, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetOverlappedResult(IntPtr hFile, IntPtr lpOverlapped,
            out int lpNumberOfBytesTransferred, [MarshalAs(UnmanagedType.Bool)] bool bWait);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CancelIoEx(IntPtr hFile, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr CreateEventW(IntPtr lpEventAttributes, [MarshalAs(UnmanagedType.Bool)] bool bManualReset,
            [MarshalAs(UnmanagedType.Bool)] bool bInitialState, IntPtr lpName);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetNamedPipeServerProcessId(IntPtr hPipe, out uint serverProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr OpenProcess(uint dwDesiredAccess, [MarshalAs(UnmanagedType.Bool)] bool bInheritHandle,
            uint dwProcessId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool QueryFullProcessImageNameW(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName,
            ref int lpdwSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetProcessTimes(IntPtr hProcess, out long lpCreationTime, out long lpExitTime,
            out long lpKernelTime, out long lpUserTime);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ProcessIdToSessionId(uint dwProcessId, out uint pSessionId);

        [DllImport("kernel32.dll")]
        internal static extern uint GetCurrentProcessId();

        [DllImport("kernel32.dll")]
        internal static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll")]
        internal static extern void GetSystemTimeAsFileTime(out long lpSystemTimeAsFileTime);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetTokenInformation(IntPtr tokenHandle, int tokenInformationClass,
            IntPtr tokenInformation, int tokenInformationLength, out int returnLength);

        [DllImport("advapi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EqualSid(IntPtr pSid1, IntPtr pSid2);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool QueryPerformanceCounter(out long lpPerformanceCount);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool QueryPerformanceFrequency(out long lpFrequency);
    }

    /// <summary>Milliseconds since this class was first used; never jumps (unlike the wall clock).</summary>
    public static class Clock
    {
        private static readonly long Frequency;
        private static readonly long Origin;

        static Clock()
        {
            Native.QueryPerformanceFrequency(out Frequency);
            Native.QueryPerformanceCounter(out Origin);
            if (Frequency <= 0) { Frequency = 1000; }
        }

        /// <summary>Fix the origin now (the first use of the class does it; this just names the intent).</summary>
        public static void Start()
        {
        }

        public static long Ms
        {
            get
            {
                long now;
                Native.QueryPerformanceCounter(out now);
                return (now - Origin) * 1000 / Frequency;
            }
        }

        /// <summary>Milliseconds between the creation of this process and now (runtime start-up included).</summary>
        internal static long SinceProcessStart()
        {
            long created, exit, kernel, user, now;
            if (!Native.GetProcessTimes(Native.GetCurrentProcess(), out created, out exit, out kernel, out user)) { return -1; }
            Native.GetSystemTimeAsFileTime(out now);
            return (now - created) / 10000;
        }
    }
}
