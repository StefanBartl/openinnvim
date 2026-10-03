// Focus.cs - FOCUS_TERMINAL: raise the window that hosts the instance a file was sent to.
//
// Best effort, never an error. A TUI session is nvim (core) -> nvim (UI client) -> shell -> terminal;
// the window belongs to an ancestor process (WezTerm, Windows Terminal) or, for a GUI such as
// Neovide, to the direct parent. Limit: several windows of one terminal process cannot be told apart.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace OpenInNvim
{
    public static class Focus
    {
        private const uint Th32csSnapProcess = 0x00000002;
        private const int SwRestore = 9;
        private const int MaxDepth = 12;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ProcessEntry32
        {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32FirstW(IntPtr hSnapshot, ref ProcessEntry32 lppe);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32NextW(IntPtr hSnapshot, ref ProcessEntry32 lppe);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
        [DllImport("user32.dll")]
        private static extern int GetWindowTextLengthW(IntPtr hWnd);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        /// <summary>True when a window was found and Windows accepted the request.</summary>
        public static bool Raise(int nvimPid)
        {
            try
            {
                if (nvimPid <= 0) { return false; }
                IntPtr hwnd = FindHostWindow(nvimPid);
                if (hwnd == IntPtr.Zero)
                {
                    Log.Line("focus: no window found for pid " + nvimPid);
                    return false;
                }
                if (IsIconic(hwnd)) { ShowWindow(hwnd, SwRestore); }
                // This process was started by the user's click, so it may hand the foreground on.
                bool ok = SetForegroundWindow(hwnd);
                Log.Line("focus: window " + hwnd.ToInt64() + (ok ? " raised" : " not raised (Windows refused)"));
                return ok;
            }
            catch (Exception ex)
            {
                Log.Line("focus failed: " + ex.Message);
                return false;
            }
        }

        /// <summary>The first visible, titled top-level window of the process or of an ancestor.</summary>
        public static IntPtr FindHostWindow(int pid)
        {
            Dictionary<uint, uint> parentOf = Parents();
            Dictionary<uint, IntPtr> windowOf = Windows();
            Dictionary<uint, bool> seen = new Dictionary<uint, bool>();
            uint cur = (uint)pid;
            for (int depth = 0; depth < MaxDepth; depth++)
            {
                IntPtr hwnd;
                if (windowOf.TryGetValue(cur, out hwnd)) { return hwnd; }
                uint parent;
                if (!parentOf.TryGetValue(cur, out parent) || parent == 0 || seen.ContainsKey(parent)) { break; }
                // Windows keeps the parent id after the parent exits and reuses ids: a "parent" that is
                // younger than its child is somebody else.
                if (!OlderThan(parent, cur)) { break; }
                seen[parent] = true;
                cur = parent;
            }
            return IntPtr.Zero;
        }

        private static bool OlderThan(uint parent, uint child)
        {
            long p, c;
            if (!CreationTime(parent, out p) || !CreationTime(child, out c)) { return false; }
            return p <= c;
        }

        private static bool CreationTime(uint pid, out long created)
        {
            created = 0;
            IntPtr h = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (h == IntPtr.Zero) { return false; }
            try
            {
                long exit, kernel, user;
                return Native.GetProcessTimes(h, out created, out exit, out kernel, out user);
            }
            finally { Native.CloseHandle(h); }
        }

        private static Dictionary<uint, uint> Parents()
        {
            Dictionary<uint, uint> map = new Dictionary<uint, uint>();
            IntPtr snap = CreateToolhelp32Snapshot(Th32csSnapProcess, 0);
            if (snap == Native.InvalidHandle) { return map; }
            try
            {
                ProcessEntry32 e = new ProcessEntry32();
                e.dwSize = (uint)Marshal.SizeOf(typeof(ProcessEntry32));
                if (Process32FirstW(snap, ref e))
                {
                    do { map[e.th32ProcessID] = e.th32ParentProcessID; }
                    while (Process32NextW(snap, ref e));
                }
            }
            finally { Native.CloseHandle(snap); }
            return map;
        }

        private static Dictionary<uint, IntPtr> Windows()
        {
            Dictionary<uint, IntPtr> map = new Dictionary<uint, IntPtr>();
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                // A main window: visible, has a title, and no owner (GW_OWNER = 4).
                if (IsWindowVisible(hWnd) && GetWindowTextLengthW(hWnd) > 0 && GetWindow(hWnd, 4) == IntPtr.Zero)
                {
                    uint pid;
                    GetWindowThreadProcessId(hWnd, out pid);
                    if (pid != 0 && !map.ContainsKey(pid)) { map[pid] = hWnd; }
                }
                return true;
            }, IntPtr.Zero);
            return map;
        }
    }
}
