// Spawner.cs - starting a new Neovim ("new" mode, and "current" when no instance is usable).
//
// Package 1 holds the seam only: the test hooks and the Neovim command line. Choosing and starting
// a terminal (WezTerm, Windows Terminal, plain console) is package 2.

using System;
using System.Collections.Generic;
using System.IO;

namespace OpenInNvim
{
    public sealed class SpawnPlan
    {
        public string Exe;
        /// <summary>The finished command line after the program (CommandLineToArgvW quoting).</summary>
        public string Arguments;
        public string WorkDir;
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

            SpawnPlan plan = Plan(target, cfg, listenPipe);
            if (plan == null)
            {
                // PACKAGE 2: tell the person with a message box (unless hooks.NoUi); nobody reads stderr of a click.
                Log.Line("nothing startable: Neovim not found (NVIM_BIN = " + cfg.NvimBin + ")");
                Output.Error("OpenInNvim: Neovim not found (NVIM_BIN = " + cfg.NvimBin + ")");
                return 1;
            }

            if (hooks.SpawnDryRun)
            {
                Output.Line("spawn: " + plan.Exe + " " + plan.Arguments);
                Output.Line("spawn-cwd: " + plan.WorkDir);
                Log.Line("spawn (dry run): " + plan.Exe + " " + plan.Arguments);
                return 0;
            }

            // PACKAGE 2: start plan.Exe (in WezTerm, Windows Terminal or its own console) with plan.WorkDir.
            Log.Line("starting a new instance is not built yet (package 2)");
            Output.Error("OpenInNvim: starting a new instance is not built yet");
            return 1;
        }

        /// <summary>
        /// The Neovim command line: no --listen by default (the new instance has its default pipe and the
        /// next click finds it); "--" before the file so a name starting with "-" is not read as an option.
        /// </summary>
        public static SpawnPlan Plan(Target target, Config cfg, string listenPipe)
        {
            string nvim = null;
            try
            {
                if (!string.IsNullOrEmpty(cfg.NvimBin) && File.Exists(cfg.NvimBin)) { nvim = Path.GetFullPath(cfg.NvimBin); }
            }
            catch (Exception) { nvim = null; }
            if (nvim == null) { nvim = CommandLine.FindOnPath("nvim"); }
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
    }
}
