// Shared by OpenInNvim-Setup.exe and uninstall.exe: what is installed where, and the registry layout.
// C# 5 (the compiler that ships with Windows): no string interpolation, no ?., no nameof, no
// expression-bodied members. ASCII only. Per user: nothing here needs administrator rights.
//
// The registry layout is the same as install.ps1 / register-nvim-default-app.ps1 /
// install-icons-for-progids.ps1 write, so either way of installing can be undone by either uninstaller.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace OpenInNvimSetup
{
    internal static class Product
    {
        public const string Name = "OpenInNvim";
        public const string ExeName = "OpenInNvim.exe";
        public const string UninstallerName = "uninstall.exe";
        public const string ConfigName = "open-in-nvim.ini";
        public const string ManifestName = "install.manifest.txt";
        public const string NewIcon = "new-session.ico";
        public const string CurrentIcon = "current-session.ico";
        public const string Publisher = "Stefan Bartl";
        public const string Url = "https://github.com/StefanBartl/openinnvim";

        // The files this installer writes next to each other (the config is handled separately).
        public static readonly string[] Files = new string[] { ExeName, UninstallerName, NewIcon, CurrentIcon };

        // Files of the old VBS + PowerShell version; removed from an install folder that still has them.
        public static readonly string[] OldFiles = new string[]
        {
            "open-in-nvim.vbs", "open-in-nvim-current.vbs", "open-in-nvim.ps1", "open-in-nvim-current.ps1",
            "open-in-nvim.lib.ps1"
        };

        public static string Version()
        {
            try
            {
                FileVersionInfo info = FileVersionInfo.GetVersionInfo(Assembly.GetExecutingAssembly().Location);
                if (!string.IsNullOrEmpty(info.ProductVersion)) { return info.ProductVersion; }
                if (!string.IsNullOrEmpty(info.FileVersion)) { return info.FileVersion; }
            }
            catch (Exception) { }
            return "0.0.0";
        }

        public static string DefaultDir()
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Name);
        }
    }

    // Registry keys below HKCU. The defaults are the real ones; only the tests pass others.
    internal sealed class Keys
    {
        public string Classes = "Software\\Classes";
        public string Software = "Software";
        public string Uninstall = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenInNvim";

        public bool IsReal()
        {
            return Classes == "Software\\Classes" && Software == "Software"
                && Uninstall == "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenInNvim";
        }
    }

    // Command line: /S, /D=<dir>, /DEFAULT=new|current, /NVIM=<nvim.exe>, /REMOVECONFIG, /LOG=<file>
    // and the internal ones (/DIR, /RUN, /PARENT, /CLASSESKEY, /SOFTWAREKEY, /UNINSTALLKEY).
    internal sealed class Args
    {
        public bool Silent;
        public string Dir = "";          // /D= (setup) or /DIR= (uninstaller stage 2)
        public string DefaultMode = "";  // "", "new", "current"
        public string Nvim = "";
        public bool RemoveConfig;
        public string LogFile = "";
        public bool Run;                 // uninstaller stage 2
        public int Parent;
        public Keys Keys = new Keys();
        public List<string> Unknown = new List<string>();

        public static Args Parse(string[] argv)
        {
            Args a = new Args();
            for (int i = 0; i < argv.Length; i++)
            {
                string raw = argv[i];
                if (raw.Length < 2 || (raw[0] != '/' && raw[0] != '-')) { a.Unknown.Add(raw); continue; }
                string body = raw.TrimStart('/', '-');
                string name = body;
                string value = "";
                int eq = body.IndexOf('=');
                if (eq >= 0) { name = body.Substring(0, eq); value = body.Substring(eq + 1).Trim('"'); }
                switch (name.ToUpperInvariant())
                {
                    case "S": case "SILENT": a.Silent = true; break;
                    case "D": case "DIR": a.Dir = value; break;
                    case "DEFAULT": a.DefaultMode = value.ToLowerInvariant(); break;
                    case "NVIM": a.Nvim = value; break;
                    case "REMOVECONFIG": a.RemoveConfig = true; break;
                    case "LOG": a.LogFile = value; break;
                    case "RUN": a.Run = true; break;
                    case "PARENT": int.TryParse(value, out a.Parent); break;
                    case "CLASSESKEY": a.Keys.Classes = value; break;
                    case "SOFTWAREKEY": a.Keys.Software = value; break;
                    case "UNINSTALLKEY": a.Keys.Uninstall = value; break;
                    default: a.Unknown.Add(raw); break;
                }
            }
            // /DEFAULT=yes (or 1, true) offers both entries; new|current names the mode of the generic
            // Neovim.TextFile entry (the two single-mode entries are always both written).
            if (a.DefaultMode == "yes" || a.DefaultMode == "1" || a.DefaultMode == "true") { a.DefaultMode = "current"; }
            if (a.DefaultMode != "" && a.DefaultMode != "new" && a.DefaultMode != "current" && a.DefaultMode != "none")
            {
                a.Unknown.Add("/DEFAULT=" + a.DefaultMode);
                a.DefaultMode = "";
            }
            if (a.DefaultMode == "none") { a.DefaultMode = ""; }
            return a;
        }
    }

    internal static class Log
    {
        private static string file = "";

        public static void Open(string path) { file = path ?? ""; }

        public static void Line(string text)
        {
            if (file.Length == 0) { return; }
            try { File.AppendAllText(file, text + "\r\n", new UTF8Encoding(false)); }
            catch (Exception) { }
        }
    }

    internal static class Res
    {
        public static Stream Open(string name)
        {
            Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
            if (s == null) { throw new InvalidOperationException("This installer is missing its built-in file " + name + "."); }
            return s;
        }

        public static string ReadText(string name)
        {
            using (StreamReader r = new StreamReader(Open(name), new UTF8Encoding(false)))
            {
                return r.ReadToEnd();
            }
        }

        // Write a built-in file next to its neighbours. A running exe cannot be overwritten or deleted but it
        // can be renamed: that is how an update over a running launcher works.
        public static void Extract(string name, string dest)
        {
            string tmp = dest + ".new";
            using (Stream s = Open(name))
            using (FileStream f = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                s.CopyTo(f);
            }
            Fs.Replace(tmp, dest);
        }
    }

    internal static class Fs
    {
        // Move tmp over dest. If dest is locked: rename it out of the way (the new file takes its name)
        // and try to delete the renamed one; a leftover *.old-* file is harmless and removed next time.
        public static void Replace(string tmp, string dest)
        {
            if (File.Exists(dest))
            {
                if (!TryDelete(dest))
                {
                    string aside = dest + ".old-" + Guid.NewGuid().ToString("N").Substring(0, 8);
                    File.Move(dest, aside);
                    TryDelete(aside);
                }
            }
            File.Move(tmp, dest);
        }

        // Delete with a few retries (a launcher that has just exited may still hold its file for a moment).
        public static bool TryDelete(string path)
        {
            for (int i = 0; i < 6; i++)
            {
                try
                {
                    if (!File.Exists(path)) { return true; }
                    File.SetAttributes(path, FileAttributes.Normal);
                    File.Delete(path);
                    return true;
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                System.Threading.Thread.Sleep(200);
            }
            return !File.Exists(path);
        }

        public static void RemoveLeftovers(string dir)
        {
            try
            {
                foreach (string f in Directory.GetFiles(dir, "*.old-*"))
                {
                    TryDelete(f);
                }
            }
            catch (Exception) { }
        }

        public static string Normalize(string dir)
        {
            if (string.IsNullOrWhiteSpace(dir)) { throw new ArgumentException("No install folder given."); }
            if (dir.IndexOf('"') >= 0 || dir.IndexOf('%') >= 0) { throw new ArgumentException("The folder name must not contain quotes or %."); }
            if (!Path.IsPathRooted(dir)) { throw new ArgumentException("The install folder must be an absolute path: " + dir); }
            string full = Path.GetFullPath(dir).TrimEnd('\\', '/');
            string root = Path.GetPathRoot(full) ?? "";
            if (full.Length <= root.TrimEnd('\\').Length) { throw new ArgumentException("A drive root is not a valid install folder."); }
            return full;
        }

        // A repository (or anything under one) is never an install folder: both installers would write
        // and delete files there.
        public static bool IsRepository(string dir)
        {
            return Directory.Exists(Path.Combine(dir, ".git")) || File.Exists(Path.Combine(dir, ".git"));
        }
    }

    internal static class Ini
    {
        // Replace (or append) "KEY = value"; a commented-out "# KEY = ..." line is taken over.
        public static string Set(string text, string key, string value)
        {
            string line = key + " = " + value;
            Regex rx = new Regex("^[ \\t]*#?[ \\t]*" + Regex.Escape(key) + "[ \\t]*=.*$", RegexOptions.Multiline);
            if (rx.IsMatch(text))
            {
                return rx.Replace(text, delegate (Match m) { return line; }, 1);
            }
            return text.TrimEnd() + "\r\n" + line + "\r\n";
        }
    }

    internal static class Nvim
    {
        // First nvim.exe found: PATH, the official installer, winget, scoop. Null when there is none.
        public static string Find()
        {
            string path = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (string part in path.Split(';'))
            {
                string dir = part.Trim().Trim('"');
                if (dir.Length == 0) { continue; }
                try
                {
                    string candidate = Path.Combine(dir, "nvim.exe");
                    if (File.Exists(candidate)) { return Path.GetFullPath(candidate); }
                }
                catch (Exception) { }
            }
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string[] fixedPlaces = new string[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Neovim\\bin\\nvim.exe"),
                Path.Combine(local, "Programs\\Neovim\\bin\\nvim.exe"),
                Path.Combine(local, "Microsoft\\WinGet\\Links\\nvim.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "scoop\\apps\\neovim\\current\\bin\\nvim.exe")
            };
            foreach (string c in fixedPlaces)
            {
                if (File.Exists(c)) { return c; }
            }
            return null;
        }
    }

    internal static class Shell
    {
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

        // Explorer keeps the old commands in memory until it is told. Not for a throw-away test key: nothing
        // real changed and the broadcast makes every Explorer window refresh its icons.
        public static void AssocChanged(Keys keys)
        {
            if (!keys.IsReal()) { return; }
            try { SHChangeNotify(0x08000000, 0x1000, IntPtr.Zero, IntPtr.Zero); }   // SHCNE_ASSOCCHANGED, SHCNF_FLUSH
            catch (Exception ex) { Log.Line("SHChangeNotify failed: " + ex.Message); }
        }
    }

    // All registry writes and removals, per user (HKCU).
    internal static class Reg
    {
        private static readonly string[] MenuNames = new string[] { "Open_in_Neovim_new", "Open_in_Neovim_current" };
        private static readonly string[] Legacy = new string[]
        {
            "Open_in_Neovim", "Open_in_Neovim_nvr", "Open_in_Neovim_new_hidden", "Open_in_Neovim_Debug"
        };
        // "%1" is the clicked item, "%V" the folder whose background was clicked.
        private static readonly string[][] Targets = new string[][]
        {
            new string[] { "*\\shell", "%1" },
            new string[] { "Directory\\shell", "%1" },
            new string[] { "Directory\\Background\\shell", "%V" }
        };
        public static readonly string[] ProgIds = new string[] { "Neovim.TextFile", "Neovim.TextFile.New", "Neovim.TextFile.Current" };

        private static string Label(string mode)
        {
            return mode == "new" ? "Open with Neovim (new instance)" : "Open with Neovim (current instance)";
        }

        private static string Entry(string mode)
        {
            return mode == "new" ? MenuNames[0] : MenuNames[1];
        }

        // The six Explorer menu entries; older names of this tool are removed so a menu never shows duplicates.
        public static void WriteContextEntries(Keys keys, string exe, string icon)
        {
            RegistryKey hkcu = Registry.CurrentUser;
            foreach (string[] t in Targets)
            {
                foreach (string old in Legacy)
                {
                    hkcu.DeleteSubKeyTree(keys.Classes + "\\" + t[0] + "\\" + old, false);
                }
                foreach (string mode in new string[] { "new", "current" })
                {
                    string key = keys.Classes + "\\" + t[0] + "\\" + Entry(mode);
                    // The program by its full, quoted path: nothing is looked up at click time.
                    string command = "\"" + exe + "\" " + mode + " \"" + t[1] + "\"";
                    using (RegistryKey k = hkcu.CreateSubKey(key))
                    {
                        k.SetValue("", Label(mode));
                        k.SetValue("Icon", icon);
                    }
                    using (RegistryKey c = hkcu.CreateSubKey(key + "\\command"))
                    {
                        c.SetValue("", command);
                    }
                    Log.Line("write HKCU\\" + key);
                }
            }
        }

        public static int RemoveContextEntries(Keys keys)
        {
            RegistryKey hkcu = Registry.CurrentUser;
            int removed = 0;
            foreach (string[] t in Targets)
            {
                foreach (string n in MenuNames)
                {
                    string key = keys.Classes + "\\" + t[0] + "\\" + n;
                    if (Exists(key)) { hkcu.DeleteSubKeyTree(key, false); removed++; Log.Line("remove HKCU\\" + key); }
                }
            }
            return removed;
        }

        private static bool Exists(string sub)
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(sub))
            {
                return k != null;
            }
        }

        // Default app: Neovim.TextFile (the chosen mode, with the file types), plus the two single-mode ProgIDs
        // so both can be picked in Settings -> Default apps.
        public static void RegisterDefaultApp(Keys keys, string mode, string exe, string dir, List<string> extensions)
        {
            WriteProgId(keys, "Neovim.TextFile", Label2(mode), Path.Combine(dir, mode == "new" ? Product.NewIcon : Product.CurrentIcon), mode, exe, extensions);
            WriteProgId(keys, "Neovim.TextFile.New", Label2("new"), Path.Combine(dir, Product.NewIcon), "new", exe, extensions);
            WriteProgId(keys, "Neovim.TextFile.Current", Label2("current"), Path.Combine(dir, Product.CurrentIcon), "current", exe, extensions);
        }

        private static string Label2(string mode)
        {
            return mode == "new" ? "Neovim (new instance)" : "Neovim (current instance)";
        }

        private static void WriteProgId(Keys keys, string progId, string display, string icon, string mode, string exe, List<string> extensions)
        {
            RegistryKey hkcu = Registry.CurrentUser;
            string classes = keys.Classes + "\\" + progId;
            using (RegistryKey k = hkcu.CreateSubKey(classes))
            {
                k.SetValue("", display);
                k.SetValue("FriendlyAppName", display);
            }
            using (RegistryKey k = hkcu.CreateSubKey(classes + "\\DefaultIcon")) { k.SetValue("", icon); }
            using (RegistryKey k = hkcu.CreateSubKey(classes + "\\shell\\open\\command"))
            {
                k.SetValue("", "\"" + exe + "\" " + mode + " \"%1\"");
            }
            string cap = keys.Software + "\\" + progId + "\\Capabilities";
            using (RegistryKey k = hkcu.CreateSubKey(cap))
            {
                k.SetValue("ApplicationName", display);
                k.SetValue("ApplicationDescription", "Text editor based on Neovim");
            }
            using (RegistryKey k = hkcu.CreateSubKey(cap + "\\FileAssociations"))
            {
                foreach (string ext in extensions) { k.SetValue(ext, progId); }
            }
            using (RegistryKey k = hkcu.CreateSubKey(keys.Software + "\\RegisteredApplications"))
            {
                k.SetValue(progId, keys.Software + "\\" + progId + "\\Capabilities");
            }
            Log.Line("register default app " + progId);
        }

        // Only the three ProgIDs of this tool, their Capabilities and their RegisteredApplications values.
        public static int RemoveDefaultApp(Keys keys)
        {
            RegistryKey hkcu = Registry.CurrentUser;
            int removed = 0;
            foreach (string id in ProgIds)
            {
                foreach (string key in new string[] { keys.Classes + "\\" + id, keys.Software + "\\" + id })
                {
                    if (Exists(key)) { hkcu.DeleteSubKeyTree(key, false); removed++; Log.Line("remove HKCU\\" + key); }
                }
                using (RegistryKey ra = hkcu.OpenSubKey(keys.Software + "\\RegisteredApplications", true))
                {
                    if (ra != null && ra.GetValue(id) != null)
                    {
                        ra.DeleteValue(id, false);
                        removed++;
                        Log.Line("remove RegisteredApplications value " + id);
                    }
                }
            }
            return removed;
        }

        // "Apps" in Windows Settings lists the program through this key.
        public static void WriteUninstallKey(Keys keys, string dir, string exe, long sizeBytes)
        {
            string uninstaller = Path.Combine(dir, Product.UninstallerName);
            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(keys.Uninstall))
            {
                k.SetValue("DisplayName", Product.Name);
                k.SetValue("DisplayVersion", Product.Version());
                k.SetValue("Publisher", Product.Publisher);
                k.SetValue("URLInfoAbout", Product.Url);
                k.SetValue("InstallLocation", dir);
                k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                k.SetValue("DisplayIcon", Path.Combine(dir, Product.CurrentIcon));
                k.SetValue("UninstallString", "\"" + uninstaller + "\"");
                k.SetValue("QuietUninstallString", "\"" + uninstaller + "\" /S");
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                k.SetValue("EstimatedSize", (int)Math.Max(1, sizeBytes / 1024), RegistryValueKind.DWord);
            }
            Log.Line("write HKCU\\" + keys.Uninstall);
        }

        public static string ReadInstallLocation(Keys keys)
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(keys.Uninstall))
            {
                if (k == null) { return null; }
                object v = k.GetValue("InstallLocation");
                return v == null ? null : v.ToString();
            }
        }

        public static bool RemoveUninstallKey(Keys keys)
        {
            if (!Exists(keys.Uninstall)) { return false; }
            Registry.CurrentUser.DeleteSubKeyTree(keys.Uninstall, false);
            Log.Line("remove HKCU\\" + keys.Uninstall);
            return true;
        }
    }

    internal static class Extensions
    {
        // The list of file types lives in file-extensions.ps1 (one copy, shared with the scripts); the setup
        // carries that file as a resource and reads the quoted '.ext' tokens out of it.
        public static List<string> Read()
        {
            List<string> list = new List<string>();
            foreach (string raw in Res.ReadText("file-extensions.ps1").Split('\n'))
            {
                string line = raw;
                int hash = line.IndexOf('#');
                if (hash >= 0) { line = line.Substring(0, hash); }
                foreach (Match m in Regex.Matches(line, "'(\\.[^']+)'"))
                {
                    string e = m.Groups[1].Value;
                    if (!list.Contains(e)) { list.Add(e); }
                }
            }
            return list;
        }
    }
}
