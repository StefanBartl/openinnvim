// Target.cs - what was clicked: an existing file, an existing folder, or a path that does not exist yet.

using System;
using System.IO;

namespace OpenInNvim
{
    public enum TargetKind
    {
        File = 0,
        Folder = 1,
        /// <summary>The path does not exist: Neovim opens an empty buffer under that name.</summary>
        NewFile = 2
    }

    public sealed class Target
    {
        public TargetKind Kind;
        /// <summary>Absolute path, used literally from here on.</summary>
        public string Path;
        /// <summary>Working directory for a new instance: the folder itself, or the file's folder.</summary>
        public string WorkDir;

        /// <summary>
        /// The path is taken LITERALLY: no %VAR% expansion ("%TEMP%x" is a legal folder name), no
        /// wildcards. <paramref name="given"/> null or empty means the process working directory.
        /// </summary>
        public static Target Resolve(string given, string processDir)
        {
            Target t = new Target();
            string p = string.IsNullOrEmpty(given) ? processDir : given;

            // A bare "C:" means "the current directory on C:", which for a hidden launcher is an accident
            // of how it was started. Nobody clicks that; the drive root is what was meant.
            if (p.Length == 2 && p[1] == ':' && char.IsLetter(p[0])) { p = p + "\\"; }

            string full;
            try { full = System.IO.Path.GetFullPath(p); }
            catch (Exception) { full = p; }

            if (DirectoryExists(full))
            {
                t.Kind = TargetKind.Folder;
                t.Path = TrimSeparators(full);
                t.WorkDir = t.Path;
                return t;
            }

            if (FileExists(full))
            {
                t.Kind = TargetKind.File;
                t.Path = full;
                t.WorkDir = ParentOf(full);
                if (t.WorkDir == null) { t.WorkDir = processDir; }
                return t;
            }

            t.Kind = TargetKind.NewFile;
            t.Path = TrimSeparators(full);
            string parent = ParentOf(t.Path);
            t.WorkDir = (parent != null && DirectoryExists(parent)) ? parent : processDir;
            return t;
        }

        // The runtime of a program built without a TargetFrameworkAttribute (our csc call) uses the
        // .NET 4.0 path rules: for a path of 248+ characters GetFullPath and GetDirectoryName throw and
        // File/Directory.Exists answer false, so an existing long file or folder was taken for a NEW file
        // (wrong kind, wrong working directory). The "\\?\" form has no such limit and is only used when
        // the plain form says no.

        /// <summary>The "\\?\" spelling of an absolute path, or null when it has none.</summary>
        public static string LongForm(string path)
        {
            if (path == null || path.Length < 4) { return null; }
            if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) { return path; }
            if (path.StartsWith(@"\\.\", StringComparison.Ordinal)) { return null; }
            string p = path.Replace('/', '\\');
            if (p.StartsWith(@"\\", StringComparison.Ordinal)) { return @"\\?\UNC\" + p.Substring(2); }
            if (p.Length > 2 && p[1] == ':' && p[2] == '\\' && char.IsLetter(p[0])) { return @"\\?\" + p; }
            return null;
        }

        public static bool DirectoryExists(string path)
        {
            try
            {
                if (Directory.Exists(path)) { return true; }
                return LongAttributes(path) == 1;
            }
            catch (Exception) { return false; }
        }

        public static bool FileExists(string path)
        {
            try
            {
                if (File.Exists(path)) { return true; }
                return LongAttributes(path) == 0;
            }
            catch (Exception) { return false; }
        }

        /// <summary>1 folder, 0 file, -1 nothing there (or the path is not long enough to need this).</summary>
        private static int LongAttributes(string path)
        {
            // The runtime's own Exists calls cannot take the "\\?\" form under the old rules; Win32 can.
            string longForm = path.Length >= 240 ? LongForm(path) : null;
            if (longForm == null) { return -1; }
            uint attrs = Native.GetFileAttributesW(longForm);
            if (attrs == 0xFFFFFFFF) { return -1; }
            return (attrs & 0x10) != 0 ? 1 : 0;
        }

        /// <summary>"C:\dir\" becomes "C:\dir"; a root ("C:\", "\\server\share") is left alone.</summary>
        public static string TrimSeparators(string path)
        {
            int rootLength = 0;
            try
            {
                string root = System.IO.Path.GetPathRoot(path);
                if (root != null) { rootLength = root.Length; }
            }
            catch (Exception) { rootLength = 0; }
            if (rootLength < 1) { rootLength = 1; }
            int end = path.Length;
            while (end > rootLength && (path[end - 1] == '\\' || path[end - 1] == '/')) { end--; }
            return end == path.Length ? path : path.Substring(0, end);
        }

        private static string ParentOf(string path)
        {
            try { return System.IO.Path.GetDirectoryName(path); }
            catch (Exception)
            {
                // Too long for the runtime's path rules: the folder is everything before the last separator.
                int cut = path.LastIndexOf('\\');
                return cut > 2 ? path.Substring(0, cut) : null;
            }
        }
    }
}
