// CommandLine.cs - reading our own command line, writing someone else's, and finding programs on PATH.

using System;
using System.IO;
using System.Text;

namespace OpenInNvim
{
    public sealed class ParsedCommandLine
    {
        /// <summary>Lower-cased mode token ("current", "new"), or "" when there is none.</summary>
        public string Mode = "";
        /// <summary>The path exactly as given (quotes removed), or null when none was given.</summary>
        public string Path;
    }

    public static class CommandLine
    {
        /// <summary>
        /// Split the RAW command line into program, mode and "the rest is the path".
        /// args[] is useless here: Explorer writes "C:\" for a drive root, and the C runtime rules read
        /// the backslash as an escape for the closing quote (the argument becomes C:"). A file name cannot
        /// contain a double quote, so taking everything after the mode and dropping the quotes is exact.
        /// </summary>
        public static ParsedCommandLine Parse(string raw)
        {
            ParsedCommandLine result = new ParsedCommandLine();
            if (raw == null) { return result; }
            int n = raw.Length;
            int i = 0;

            // Program token: quotes toggle, white space outside quotes ends it.
            while (i < n && IsBlank(raw[i])) { i++; }
            bool quoted = false;
            while (i < n && (quoted || !IsBlank(raw[i])))
            {
                if (raw[i] == '"') { quoted = !quoted; }
                i++;
            }

            while (i < n && IsBlank(raw[i])) { i++; }
            int modeStart = i;
            while (i < n && !IsBlank(raw[i])) { i++; }
            result.Mode = raw.Substring(modeStart, i - modeStart).Trim('"').ToLowerInvariant();

            while (i < n && IsBlank(raw[i])) { i++; }
            int end = n;
            while (end > i && IsBlank(raw[end - 1])) { end--; }
            if (end > i)
            {
                string rest = raw.Substring(i, end - i);
                if (rest.Length >= 2 && rest[0] == '"' && rest[rest.Length - 1] == '"') { rest = rest.Substring(1, rest.Length - 2); }
                // A quote that is still there cannot belong to the name; a stray one must not end up in a buffer name.
                if (rest.IndexOf('"') >= 0) { rest = rest.Replace("\"", ""); }
                if (rest.Length > 0) { result.Path = rest; }
            }
            return result;
        }

        private static bool IsBlank(char c)
        {
            return c == ' ' || c == '\t';
        }

        /// <summary>
        /// Quote one argument by the CommandLineToArgvW rules: backslashes are literal except in front of a
        /// double quote, so a run of them before a quote, or at the end of the argument, is doubled.
        /// </summary>
        public static string QuoteArg(string arg)
        {
            if (string.IsNullOrEmpty(arg)) { return "\"\""; }
            StringBuilder sb = new StringBuilder(arg.Length + 8);
            sb.Append('"');
            int run = 0;
            for (int i = 0; i < arg.Length; i++)
            {
                char c = arg[i];
                if (c == '\\') { run++; continue; }
                if (c == '"')
                {
                    sb.Append('\\', run * 2 + 1);
                    sb.Append('"');
                    run = 0;
                    continue;
                }
                if (run > 0) { sb.Append('\\', run); run = 0; }
                sb.Append(c);
            }
            if (run > 0) { sb.Append('\\', run * 2); }
            sb.Append('"');
            return sb.ToString();
        }

        public static string JoinArgs(string[] args)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < args.Length; i++)
            {
                if (i > 0) { sb.Append(' '); }
                sb.Append(QuoteArg(args[i]));
            }
            return sb.ToString();
        }

        /// <summary>
        /// Full path of a program: the name itself when it contains a directory, otherwise the first hit in
        /// the PATH directories. The current directory is NOT searched: the launcher's working directory is
        /// whatever folder was clicked, and a program lying there must never be started.
        /// </summary>
        public static string FindOnPath(string name)
        {
            return FindOnPath(name, Environment.GetEnvironmentVariable("PATH"));
        }

        public static string FindOnPath(string name, string pathVariable)
        {
            if (string.IsNullOrEmpty(name)) { return null; }
            try
            {
                if (name.IndexOf('\\') >= 0 || name.IndexOf('/') >= 0 || name.IndexOf(':') >= 0)
                {
                    return File.Exists(name) ? Path.GetFullPath(name) : null;
                }
            }
            catch (Exception) { return null; }

            string file = name.IndexOf('.') >= 0 ? name : name + ".exe";
            if (string.IsNullOrEmpty(pathVariable)) { return null; }
            string[] dirs = pathVariable.Split(';');
            for (int i = 0; i < dirs.Length; i++)
            {
                string dir = dirs[i].Trim().Trim('"');
                if (dir.Length == 0) { continue; }
                try
                {
                    if (!Path.IsPathRooted(dir)) { continue; }
                    string candidate = Path.Combine(dir, file);
                    if (File.Exists(candidate)) { return candidate; }
                }
                catch (Exception) { }
            }
            return null;
        }
    }
}
