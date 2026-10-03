// Program.cs - OpenInNvim.exe: entry point, mode dispatch, exit codes, test hooks.
//
//   OpenInNvim.exe current [path]   open the path in a running Neovim; start one when none is usable
//   OpenInNvim.exe new [path]       always start a new Neovim
//
// Exit codes: 0 opened / delivered / started; 1 usage, unreadable config or nothing startable;
// 3 nothing usable and OPEN_IN_NVIM_NO_SPAWN is set.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace OpenInNvim
{
    /// <summary>Environment switches for tests and diagnostics; none is needed for normal use.</summary>
    public sealed class Hooks
    {
        /// <summary>OPEN_IN_NVIM_DRYRUN: print the target and the usable candidates, open nothing.</summary>
        public bool DryRun;
        /// <summary>OPEN_IN_NVIM_SPAWN_DRYRUN: print the command of a new instance instead of starting it.</summary>
        public bool SpawnDryRun;
        /// <summary>OPEN_IN_NVIM_NO_SPAWN: never start anything (exit 3 instead).</summary>
        public bool NoSpawn;
        /// <summary>OPEN_IN_NVIM_NO_UI: no message boxes.</summary>
        public bool NoUi;
        /// <summary>OPEN_IN_NVIM_ALLOW_TCP: a TCP NVIM_SERVER may be used although ONLY_PIDS is set.</summary>
        public bool AllowTcp;
        /// <summary>OPEN_IN_NVIM_ONLY_PIDS: the only processes that may ever be contacted; null = no limit.</summary>
        public int[] OnlyPids;
        /// <summary>OPEN_IN_NVIM_LOG: file to append the decision log to.</summary>
        public string LogPath;
        /// <summary>USERNAME, for the stable pipe name nvim-&lt;USERNAME&gt;.</summary>
        public string UserName;

        public static Hooks FromEnvironment()
        {
            Hooks h = new Hooks();
            h.DryRun = IsSet("OPEN_IN_NVIM_DRYRUN");
            h.SpawnDryRun = IsSet("OPEN_IN_NVIM_SPAWN_DRYRUN");
            h.NoSpawn = IsSet("OPEN_IN_NVIM_NO_SPAWN");
            h.NoUi = IsSet("OPEN_IN_NVIM_NO_UI");
            h.AllowTcp = IsSet("OPEN_IN_NVIM_ALLOW_TCP");
            h.OnlyPids = ParsePids(Environment.GetEnvironmentVariable("OPEN_IN_NVIM_ONLY_PIDS"));
            h.LogPath = Environment.GetEnvironmentVariable("OPEN_IN_NVIM_LOG");
            h.UserName = Environment.GetEnvironmentVariable("USERNAME");
            return h;
        }

        private static bool IsSet(string name)
        {
            string v = Environment.GetEnvironmentVariable(name);
            return !string.IsNullOrEmpty(v) && v != "0";
        }

        /// <summary>
        /// Null when the variable is not set. A variable that is set but holds no valid PID yields an EMPTY
        /// list: "restricted to nothing" is the safe reading of a typo, "unrestricted" is not.
        /// </summary>
        public static int[] ParsePids(string value)
        {
            if (string.IsNullOrEmpty(value)) { return null; }
            List<int> pids = new List<int>();
            string[] parts = value.Split(new char[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < parts.Length; i++)
            {
                int pid;
                if (int.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out pid) && pid > 0) { pids.Add(pid); }
            }
            return pids.ToArray();
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main()
        {
            Clock.Start();
            int code;
            try
            {
                code = Run();
            }
            catch (Exception ex)
            {
                // Never let the runtime show its crash dialog for a context-menu click.
                Log.Line("fatal: " + ex.ToString());
                Output.Error("OpenInNvim: " + ex.Message);
                code = 1;
            }
            Log.Line("exit " + code.ToString(CultureInfo.InvariantCulture));
            Log.Flush();
            return code;
        }

        private static int Run()
        {
            Hooks hooks = Hooks.FromEnvironment();
            Log.Init(hooks.LogPath);
            string raw = Environment.CommandLine;
            if (Log.Enabled)
            {
                Log.Line("start: " + raw + "  (process start to here: " + Clock.SinceProcessStart().ToString(CultureInfo.InvariantCulture) + " ms)");
            }

            ParsedCommandLine cl = CommandLine.Parse(raw);
            if (cl.Mode != "current" && cl.Mode != "new")
            {
                Log.Line("usage error: mode '" + cl.Mode + "'");
                Output.Error("usage: OpenInNvim.exe current|new [path]");
                return 1;
            }

            string cfgError;
            Config cfg = Config.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "open-in-nvim.ini"), out cfgError);
            if (cfg == null)
            {
                Log.Line("config error: " + cfgError);
                Output.Error("OpenInNvim: " + cfgError);
                return 1;
            }
            for (int i = 0; i < cfg.Notes.Count; i++) { Log.Line("config: " + cfg.Notes[i]); }

            Target target = Target.Resolve(cl.Path, Environment.CurrentDirectory);
            Log.Line("target: " + KindName(target.Kind) + " " + target.Path + "  cwd: " + target.WorkDir);

            if (cl.Mode == "new")
            {
                if (hooks.DryRun)
                {
                    PrintTarget(cl.Mode, target);
                    return 0;
                }
                return Spawner.Start(target, cfg, hooks, null);
            }
            return Current(target, cfg, hooks);
        }

        private static int Current(Target target, Config cfg, Hooks hooks)
        {
            DiscoveryResult found = Discovery.Find(cfg, hooks);

            if (hooks.DryRun)
            {
                // Diagnostics want the whole picture, so every candidate is probed here, not just the first.
                PrintTarget("current", target);
                for (int i = 0; i < found.Candidates.Count; i++)
                {
                    Candidate c = found.Candidates[i];
                    string why;
                    Session s = Discovery.Connect(c, hooks, out why);
                    if (s == null)
                    {
                        Log.Line("skip " + c.Address + ": " + why);
                        continue;
                    }
                    s.Dispose();
                    Output.Line("candidate: " + c.Address + " pid=" + c.Pid.ToString(CultureInfo.InvariantCulture));
                }
                return 0;
            }

            if (cfg.InstancePick == "ask" && !Chooser.IsBuilt())
            {
                Log.Line("INSTANCE_PICK = ask: the chooser is not built yet (package 2), using the newest instance");
            }

            // Lazy: the first usable instance in order gets the file; the others are never contacted.
            for (int i = 0; i < found.Candidates.Count; i++)
            {
                Candidate c = found.Candidates[i];
                string why;
                Session s = Discovery.Connect(c, hooks, out why);
                if (s == null)
                {
                    Log.Line("skip " + c.Address + ": " + why);
                    continue;
                }
                try
                {
                    Log.Line("usable: " + c.Address + " pid=" + c.Pid.ToString(CultureInfo.InvariantCulture) + " mode=" + s.Mode);
                    string detail;
                    OpenOutcome outcome = Opener.Open(s, target, cfg, Opener.ReplyTimeoutMs, out detail);
                    if (outcome == OpenOutcome.Opened)
                    {
                        Log.Line("opened in " + c.Address + " (" + detail + ")");
                        return 0;
                    }
                    if (outcome == OpenOutcome.Delivered)
                    {
                        Log.Line("delivered to " + c.Address + ": " + detail);
                        return 0;
                    }
                    Log.Line("not opened in " + c.Address + " (" + outcome.ToString() + "): " + detail);
                }
                finally { s.Dispose(); }
            }

            Log.Line("no usable instance");
            if (hooks.NoSpawn)
            {
                Output.Line("no reachable instance");
                return 3;
            }
            return Spawner.Start(target, cfg, hooks, found.ListenPipe);
        }

        private static void PrintTarget(string mode, Target target)
        {
            Output.Line("mode: " + mode);
            Output.Line("target: " + KindName(target.Kind) + " " + target.Path);
            Output.Line("cwd: " + target.WorkDir);
        }

        private static string KindName(TargetKind kind)
        {
            switch (kind)
            {
                case TargetKind.Folder: return "folder";
                case TargetKind.File: return "file";
                default: return "newfile";
            }
        }
    }
}
