// Spawner.cs - starting a new Neovim ("new" mode, and "current" when no instance is usable).
//
// Neovim is a console program, so it needs a terminal: WezTerm, Windows Terminal, or a console of
// its own. cmd.exe is never involved: it expands %VAR% inside quoted arguments and refuses a UNC
// working directory.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace OpenInNvim
{
    public sealed class SpawnPlan
    {
        public string Exe;
        /// <summary>The finished command line after the program (CommandLineToArgvW quoting).</summary>
        public string Arguments;
        public string WorkDir;
        /// <summary>"wezterm", "wt" or "console" (which program Exe is).</summary>
        public string Terminal = "console";
    }

    public static class Spawner
    {
        /// <summary>Returns the process exit code: 0 started (or printed), 1 nothing startable, 3 suppressed.</summary>
        public static int Start(Target target, Config cfg, Hooks hooks, string listenPipe)
        {
            // The safety stop comes first: with it set no window may ever appear.
            if (hooks.NoSpawn)
            {
                Log.Line("spawn suppressed (OPEN_IN_NVIM_NO_SPAWN)");
                return 3;
            }

            string path = FullPath(hooks);
            SpawnPlan plan = Plan(target, cfg, listenPipe, path);
            if (plan == null)
            {
                string text = "Neovim not found (NVIM_BIN = " + cfg.NvimBin + ")";
                Log.Line("nothing startable: " + text);
                Output.Error("OpenInNvim: " + text);
                // Nobody reads the stderr of a context-menu click.
                Chooser.ShowError(text + "\n\nSet NVIM_BIN in open-in-nvim.ini or put nvim on PATH.", hooks);
                return 1;
            }

            SpawnPlan[] launches = Wrap(plan, cfg, path);

            if (hooks.SpawnDryRun)
            {
                Output.Line("spawn: " + plan.Exe + " " + plan.Arguments);
                Output.Line("spawn-cwd: " + plan.WorkDir);
                for (int i = 0; i < launches.Length; i++)
                {
                    Output.Line("spawn-via: " + launches[i].Terminal + " " + launches[i].Exe + " " + launches[i].Arguments);
                }
                Log.Line("spawn (dry run): " + plan.Exe + " " + plan.Arguments);
                return 0;
            }

            // In order of preference; a terminal that cannot be started falls through to the next one.
            for (int i = 0; i < launches.Length; i++)
            {
                SpawnPlan l = launches[i];
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = l.Exe;
                    psi.Arguments = l.Arguments;
                    psi.UseShellExecute = false;
                    if (Directory.Exists(l.WorkDir)) { psi.WorkingDirectory = l.WorkDir; }
                    // A console program started by this window-less process gets a console of its own.
                    psi.CreateNoWindow = false;
                    // The editor (and the terminal) get the complete PATH, not Explorer's possibly cut one.
                    psi.EnvironmentVariables["PATH"] = path;
                    using (Process p = Process.Start(psi)) { }
                    Log.Line("started via " + l.Terminal + ": " + l.Exe + " " + l.Arguments);
                    return 0;
                }
                catch (Exception ex)
                {
                    Log.Line("could not start via " + l.Terminal + " (" + l.Exe + "): " + ex.Message);
                }
            }

            Log.Line("nothing startable: no terminal and no console could be started");
            Chooser.ShowError("Neovim could not be started (" + plan.Exe + ").", hooks);
            return 1;
        }

        /// <summary>
        /// The Neovim command line: no --listen by default (the new instance has its default pipe and the
        /// next click finds it); "--" before the file so a name starting with "-" is not read as an option.
        /// </summary>
        public static SpawnPlan Plan(Target target, Config cfg, string listenPipe)
        {
            return Plan(target, cfg, listenPipe, Environment.GetEnvironmentVariable("PATH"));
        }

        public static SpawnPlan Plan(Target target, Config cfg, string listenPipe, string pathVariable)
        {
            string nvim = null;
            try
            {
                // Only a rooted path is taken as a file. A bare name is looked up on PATH, never in the
                // working directory: that is the folder that was clicked.
                if (!string.IsNullOrEmpty(cfg.NvimBin) && Path.IsPathRooted(cfg.NvimBin) && File.Exists(cfg.NvimBin)) { nvim = Path.GetFullPath(cfg.NvimBin); }
            }
            catch (Exception) { nvim = null; }
            if (nvim == null && !string.IsNullOrEmpty(cfg.NvimBin) && cfg.NvimBin.IndexOfAny(new char[] { '\\', '/', ':' }) < 0) { nvim = CommandLine.FindOnPath(cfg.NvimBin, pathVariable); }
            if (nvim == null) { nvim = CommandLine.FindOnPath("nvim", pathVariable); }
            if (nvim == null) { return null; }

            List<string> args = new List<string>();
            if (!string.IsNullOrEmpty(listenPipe))
            {
                args.Add("--listen");
                args.Add(listenPipe);
            }
            if (target.Kind != TargetKind.Folder)
            {
                args.Add("--");
                args.Add(target.Path);
            }

            SpawnPlan plan = new SpawnPlan();
            plan.Exe = nvim;
            plan.Arguments = CommandLine.JoinArgs(args.ToArray());
            plan.WorkDir = target.WorkDir;
            return plan;
        }

        /// <summary>
        /// The ways to show that Neovim, best first. TERMINAL = auto: WezTerm, Windows Terminal, console.
        /// A named terminal that is not installed falls back to the console, so a click never does nothing.
        /// </summary>
        public static SpawnPlan[] Wrap(SpawnPlan nvim, Config cfg)
        {
            return Wrap(nvim, cfg, Environment.GetEnvironmentVariable("PATH"));
        }

        public static SpawnPlan[] Wrap(SpawnPlan nvim, Config cfg, string pathVariable)
        {
            List<SpawnPlan> list = new List<SpawnPlan>();
            string t = cfg.Terminal;

            if (t == "auto" || t == "wezterm")
            {
                string wez = FindWezterm(cfg, pathVariable);
                if (wez != null)
                {
                    SpawnPlan p = new SpawnPlan();
                    p.Terminal = "wezterm";
                    p.Exe = wez;
                    p.Arguments = CommandLine.JoinArgs(new string[] { "start", "--cwd", nvim.WorkDir, "--", nvim.Exe }) + Tail(nvim.Arguments);
                    p.WorkDir = nvim.WorkDir;
                    list.Add(p);
                }
            }
            if (t == "auto" || t == "wt")
            {
                string wt = CommandLine.FindOnPath("wt", pathVariable);
                if (wt != null)
                {
                    SpawnPlan p = new SpawnPlan();
                    p.Terminal = "wt";
                    p.Exe = wt;
                    // Windows Terminal splits its command line at ";" (a command separator); "\;" is a literal one.
                    string cmd = CommandLine.JoinArgs(new string[] { "-w", "0", "nt", "-d", nvim.WorkDir, "--", nvim.Exe }) + Tail(nvim.Arguments);
                    p.Arguments = cmd.Replace(";", "\\;");
                    p.WorkDir = nvim.WorkDir;
                    list.Add(p);
                }
            }
            SpawnPlan console = new SpawnPlan();
            console.Terminal = "console";
            console.Exe = nvim.Exe;
            console.Arguments = nvim.Arguments;
            console.WorkDir = nvim.WorkDir;
            list.Add(console);
            return list.ToArray();
        }

        /// <summary>
        /// PATH as a freshly opened terminal would have it: the inherited value plus every entry of the
        /// machine and user PATH in the registry that is missing from it. Explorer hands its children a
        /// PATH that is cut short when the user PATH is very long (thousands of characters), and then
        /// neither the terminal nor git is found although both are installed.
        /// </summary>
        public static string FullPath(Hooks hooks)
        {
            string inherited = Environment.GetEnvironmentVariable("PATH") ?? "";
            if (hooks.NoPathRefresh) { return inherited; }
            try
            {
                string machine = ReadPath(Microsoft.Win32.Registry.LocalMachine, @"SYSTEM\CurrentControlSet\Control\Session Manager\Environment");
                string user = ReadPath(Microsoft.Win32.Registry.CurrentUser, "Environment");
                return MergePath(inherited, machine + ";" + user);
            }
            catch (Exception ex)
            {
                Log.Line("PATH not refreshed: " + ex.Message);
                return inherited;
            }
        }

        private static string ReadPath(Microsoft.Win32.RegistryKey root, string subKey)
        {
            using (Microsoft.Win32.RegistryKey key = root.OpenSubKey(subKey))
            {
                if (key == null) { return ""; }
                // GetValue expands %VAR% of a REG_EXPAND_SZ value by default.
                object value = key.GetValue("Path");
                return value == null ? "" : value.ToString();
            }
        }

        /// <summary>The first list, then the entries of the second that it lacks (compared without case and trailing separator).</summary>
        public static string MergePath(string first, string second)
        {
            List<string> result = new List<string>();
            Dictionary<string, bool> seen = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            string[] lists = new string[] { first ?? "", second ?? "" };
            for (int l = 0; l < lists.Length; l++)
            {
                string[] parts = lists[l].Split(';');
                for (int i = 0; i < parts.Length; i++)
                {
                    string entry = parts[i].Trim();
                    if (entry.Length == 0) { continue; }
                    string key = entry.Trim('"').TrimEnd('\\', '/');
                    if (seen.ContainsKey(key)) { continue; }
                    seen[key] = true;
                    result.Add(entry);
                }
            }
            return string.Join(";", result.ToArray());
        }

        private static string Tail(string arguments)
        {
            return string.IsNullOrEmpty(arguments) ? "" : " " + arguments;
        }

        /// <summary>
        /// wezterm-gui.exe, not wezterm.exe: the latter is a console program and would flash a console
        /// window before the terminal appears.
        /// </summary>
        private static string FindWezterm(Config cfg, string pathVariable)
        {
            try
            {
                // Same rule as NVIM_BIN: only a rooted path is taken as a file (a relative one would be
                // looked up in the clicked folder, and a program lying there would be started), and a bare
                // name is looked up on PATH.
                string bin = cfg.WeztermBin;
                if (!string.IsNullOrEmpty(bin))
                {
                    if (Path.IsPathRooted(bin))
                    {
                        if (File.Exists(bin)) { return Path.GetFullPath(bin); }
                    }
                    else if (bin.IndexOfAny(new char[] { '\\', '/', ':' }) < 0)
                    {
                        string named = CommandLine.FindOnPath(bin, pathVariable);
                        if (named != null) { return named; }
                    }
                }
            }
            catch (Exception) { }
            string gui = CommandLine.FindOnPath("wezterm-gui", pathVariable);
            if (gui != null) { return gui; }
            return CommandLine.FindOnPath("wezterm", pathVariable);
        }
    }
}
