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

            if (Directory.Exists(full))
            {
                t.Kind = TargetKind.Folder;
                t.Path = TrimSeparators(full);
                t.WorkDir = t.Path;
                return t;
            }

            if (File.Exists(full))
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
            t.WorkDir = (parent != null && Directory.Exists(parent)) ? parent : processDir;
            return t;
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
            catch (Exception) { return null; }
        }
    }
}
