// Program.cs
// Tiny launcher that forwards a file path to a VBS script located next to the exe.
// The launcher determines whether to call "open-in-nvim.vbs" (new instance) or
// "open-in-nvim-current.vbs" (current session) by inspecting its own filename.
// If the exe name contains "new" (case-insensitive), it chooses new-instance VBS;
// otherwise it chooses current-session VBS.
// This allows building two different exes from the same source and assigning
// different embedded icons and names at build/publish time.
//
// Build-time customization example (see separate instructions):
//   dotnet publish -c Release -r win-x64 /p:AssemblyName=tiny-launcher-new /p:ApplicationIcon="Logos\new-session.ico" /p:AssemblyTitle="Neovim Launcher (new instance)" -o publish\new
//   dotnet publish -c Release -r win-x64 /p:AssemblyName=tiny-launcher-current /p:ApplicationIcon="Logos\current-session.ico" /p:AssemblyTitle="Neovim Launcher (current instance)" -o publish\current
//
// English comments only inside code as requested.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

class Program
{
    /// <summary>
    /// Entry point for the tiny launcher.
    /// The launcher expects the first command-line argument to be a file path to open.
    /// It will invoke wscript.exe with the appropriate VBS script and the file path.
    /// </summary>
    /// <param name="args">Command-line arguments</param>
    /// <returns>Process exit code</returns>
    static int Main(string[] args)
    {
        try
        {
            // Validate argument presence
            if (args == null || args.Length == 0 || string.IsNullOrWhiteSpace(args[0]))
            {
                // No file provided -> exit with code 2 to indicate misuse.
                Console.Error.WriteLine("No file argument provided.");
                return 2;
            }

            // Determine the directory where the executable resides.
            // AppContext.BaseDirectory works reliably for both framework and single-file publish.
            string exeFolder = AppContext.BaseDirectory?.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

            // Fallback using Assembly location if needed.
            if (string.IsNullOrEmpty(exeFolder))
            {
                string asmLocation = Assembly.GetExecutingAssembly().Location;
                if (!string.IsNullOrEmpty(asmLocation))
                {
                    exeFolder = Path.GetDirectoryName(asmLocation);
                }
            }

            if (string.IsNullOrEmpty(exeFolder))
            {
                Console.Error.WriteLine("Could not determine executable directory.");
                return 3;
            }

            // Derive the exe filename (without path) to choose VBS behaviour.
            string exeName = Path.GetFileName(Assembly.GetEntryAssembly().Location) ?? string.Empty;

            // Choose vbs filename based on exe name containing "new" (case-insensitive).
            // This naming heuristic allows two builds (tiny-launcher-new.exe, tiny-launcher-current.exe).
            string vbsFileName;
            if (exeName.IndexOf("new", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                vbsFileName = "open-in-nvim.vbs"; // new-instance VBS
            }
            else
            {
                vbsFileName = "open-in-nvim-current.vbs"; // current-session VBS
            }

            // Compose full path to the VBS file expected to sit next to the exe.
            string vbsPath = Path.Combine(exeFolder, vbsFileName);
            vbsPath = Path.GetFullPath(vbsPath);

            if (!File.Exists(vbsPath))
            {
                Console.Error.WriteLine($"VBS script not found: {vbsPath}");
                return 4;
            }

            // Prepare the file argument (quote to be safe with spaces).
            string fileArg = $"\"{args[0]}\"";

            // Build ProcessStartInfo for wscript.exe invocation.
            var psi = new ProcessStartInfo
            {
                FileName = "wscript.exe",
                Arguments = $"//nologo \"{vbsPath}\" {fileArg}",
                UseShellExecute = false,
                CreateNoWindow = true
            };

            // Start the VBS via wscript and return immediately (do not wait).
            Process.Start(psi);

            // Return success.
            return 0;
        }
        catch (Exception ex)
        {
            // Write detailed error to stderr to help debugging.
            Console.Error.WriteLine("Launcher error: " + ex.ToString());
            return 1;
        }
    }
}

