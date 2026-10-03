// Config.cs - open-in-nvim.ini next to the exe. Every key is optional; a missing file means defaults.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace OpenInNvim
{
    public sealed class Config
    {
        /// <summary>Path of nvim.exe, or "nvim" to look on PATH.</summary>
        public string NvimBin = "nvim";
        /// <summary>auto | wezterm | wt | console</summary>
        public string Terminal = "auto";
        public string WeztermBin = "";
        /// <summary>A pipe name or host:port tried first; empty: find the instances.</summary>
        public string NvimServer = "";
        public bool PreferStablePipe = true;
        /// <summary>newest | oldest | ask</summary>
        public string InstancePick = "newest";
        /// <summary>filetree | edit</summary>
        public string FolderOpensIn = "filetree";
        public bool FocusTerminal;

        /// <summary>What the parser ignored or replaced by a default (for the log).</summary>
        public List<string> Notes = new List<string>();

        /// <summary>
        /// Read the file. Returns null and sets <paramref name="error"/> only when the file exists but cannot
        /// be read; a bad VALUE never stops a click, it falls back to the default and is noted.
        /// </summary>
        public static Config Load(string path, out string error)
        {
            error = null;
            try
            {
                if (!File.Exists(path)) { return new Config(); }
                string text;
                try
                {
                    // UTF-8 (or UTF-16 with a byte order mark). Strict, so that a file saved in the ANSI
                    // code page (what Windows PowerShell's Set-Content writes) is noticed, not garbled.
                    text = File.ReadAllText(path, new UTF8Encoding(false, true));
                }
                catch (DecoderFallbackException)
                {
                    text = File.ReadAllText(path, Encoding.Default);
                }
                return Parse(text);
            }
            catch (Exception ex)
            {
                error = "cannot read " + path + ": " + ex.Message;
                return null;
            }
        }

        /// <summary>
        /// "KEY = value" lines; "#" (or ";") starts a comment LINE. The value runs to the end of the line:
        /// "#" and ";" are legal in paths, so there are no trailing comments. One pair of quotes is
        /// stripped, then %VAR% is expanded (the config is the user's own text, unlike a clicked path).
        /// </summary>
        public static Config Parse(string text)
        {
            Config cfg = new Config();
            if (string.IsNullOrEmpty(text)) { return cfg; }
            string[] lines = text.Split('\n');
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (line.Length == 0 || line[0] == '#' || line[0] == ';') { continue; }
                int eq = line.IndexOf('=');
                if (eq < 1)
                {
                    cfg.Notes.Add("line " + (i + 1) + " ignored (no KEY = value)");
                    continue;
                }
                string key = line.Substring(0, eq).Trim().ToUpperInvariant();
                string value = line.Substring(eq + 1).Trim();
                if (value.Length >= 2 && ((value[0] == '"' && value[value.Length - 1] == '"') || (value[0] == '\'' && value[value.Length - 1] == '\'')))
                {
                    value = value.Substring(1, value.Length - 2);
                }
                value = Environment.ExpandEnvironmentVariables(value);

                switch (key)
                {
                    case "NVIM_BIN": if (value.Length > 0) { cfg.NvimBin = value; } break;
                    case "WEZTERM_BIN": cfg.WeztermBin = value; break;
                    case "NVIM_SERVER": cfg.NvimServer = value; break;
                    case "TERMINAL": cfg.Terminal = Choice(cfg, key, value, cfg.Terminal, "auto", "wezterm", "wt", "console"); break;
                    case "INSTANCE_PICK": cfg.InstancePick = Choice(cfg, key, value, cfg.InstancePick, "newest", "oldest", "ask"); break;
                    case "FOLDER_OPENS_IN": cfg.FolderOpensIn = Choice(cfg, key, value, cfg.FolderOpensIn, "filetree", "edit"); break;
                    case "PREFER_STABLE_PIPE": cfg.PreferStablePipe = Flag(cfg, key, value, cfg.PreferStablePipe); break;
                    case "FOCUS_TERMINAL": cfg.FocusTerminal = Flag(cfg, key, value, cfg.FocusTerminal); break;
                    default: cfg.Notes.Add("unknown key " + key + " ignored"); break;
                }
            }
            return cfg;
        }

        private static string Choice(Config cfg, string key, string value, string fallback, params string[] allowed)
        {
            string v = value.ToLowerInvariant();
            for (int i = 0; i < allowed.Length; i++)
            {
                if (v == allowed[i]) { return v; }
            }
            cfg.Notes.Add(key + ": '" + value + "' is not valid, using " + fallback);
            return fallback;
        }

        private static bool Flag(Config cfg, string key, string value, bool fallback)
        {
            // "$true" / "$false" are what the old PowerShell config file used.
            string v = value.ToLowerInvariant().TrimStart('$');
            if (v == "true" || v == "1" || v == "yes" || v == "on") { return true; }
            if (v == "false" || v == "0" || v == "no" || v == "off") { return false; }
            cfg.Notes.Add(key + ": '" + value + "' is not a boolean, using " + (fallback ? "true" : "false"));
            return fallback;
        }
    }
}
