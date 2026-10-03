// Log.cs - the decision log (OPEN_IN_NVIM_LOG) and stdout/stderr for a program without a console.

using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace OpenInNvim
{
    /// <summary>
    /// One line per decision: "&lt;elapsed ms&gt; &lt;text&gt;", appended to the file named by OPEN_IN_NVIM_LOG.
    /// Lines are collected in memory and written in one go, so logging costs the click nothing until the end.
    /// </summary>
    public static class Log
    {
        private static string file;
        private static StringBuilder pending;

        public static bool Enabled { get { return pending != null; } }

        public static void Init(string path)
        {
            if (string.IsNullOrEmpty(path)) { return; }
            file = path;
            pending = new StringBuilder(2048);
        }

        public static void Line(string text)
        {
            if (pending == null) { return; }
            pending.Append(Clock.Ms.ToString(CultureInfo.InvariantCulture).PadLeft(6)).Append(' ').Append(text).Append("\r\n");
        }

        /// <summary>Write what has been collected; called before any long wait and at exit.</summary>
        public static void Flush()
        {
            if (pending == null || pending.Length == 0) { return; }
            try { File.AppendAllText(file, pending.ToString(), new UTF8Encoding(false)); }
            catch (Exception) { }
            pending.Length = 0;
        }
    }

    /// <summary>
    /// A GUI-subsystem program has no console, but a redirected stdout/stderr handle still works; the tests
    /// and diagnostics read it. UTF-8, because a path can hold any character.
    /// </summary>
    public static class Output
    {
        public static void Line(string text)
        {
            Write(Console.OpenStandardOutput(), text);
        }

        public static void Error(string text)
        {
            Write(Console.OpenStandardError(), text);
        }

        private static void Write(Stream stream, string text)
        {
            try
            {
                byte[] bytes = Encoding.UTF8.GetBytes(text + "\r\n");
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush();
            }
            catch (Exception) { }
        }
    }
}
