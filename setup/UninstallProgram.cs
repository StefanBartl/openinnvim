// uninstall.exe: removes OpenInNvim (per user). Started from Settings > Apps or by double click.
//
//   uninstall.exe                a confirmation window
//   uninstall.exe /S             silent; the config file is kept
//   /REMOVECONFIG                also delete open-in-nvim.ini        /LOG=<file>
//
// A program cannot delete the file it runs from, so the first start copies itself to %TEMP% and starts
// that copy (/RUN), which removes everything once the first process has exited and then deletes itself.
// What goes: the menu entries, the three default-app ProgIDs, the "Apps" entry and the files named in
// install.manifest.txt (plain file names only, never a recursive delete). The folder goes only when it
// ends up empty. C# 5, ASCII only.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace OpenInNvimSetup
{
    internal sealed class UninstallSummary
    {
        public int Entries;
        public int DefaultApp;
        public int FilesDeleted;
        public bool ConfigKept;
        public bool FolderRemoved;
        public List<string> Leftovers = new List<string>();
    }

    internal static class Uninstaller
    {
        public static UninstallSummary Remove(Args a, string dir, bool removeConfig)
        {
            UninstallSummary s = new UninstallSummary();
            s.Entries = Reg.RemoveContextEntries(a.Keys);
            s.DefaultApp = Reg.RemoveDefaultApp(a.Keys);
            Reg.RemoveUninstallKey(a.Keys);
            Shell.AssocChanged(a.Keys);

            if (Fs.IsRepository(dir))
            {
                Log.Line("the folder is a repository, files are left alone: " + dir);
                return s;
            }

            // Plain file names only: the manifest is a file in a folder anybody can write to.
            List<string> names = new List<string>(Product.Files);
            string manifest = Path.Combine(dir, Product.ManifestName);
            if (File.Exists(manifest))
            {
                foreach (string line in File.ReadAllLines(manifest))
                {
                    string n = line.Trim();
                    if (n.Length > 0 && n == Path.GetFileName(n) && !names.Contains(n)) { names.Add(n); }
                }
            }
            else if (!File.Exists(Path.Combine(dir, Product.ExeName)))
            {
                Log.Line("no manifest and no launcher in " + dir + ": nothing deleted");
                return s;
            }
            if (!names.Contains(Product.ConfigName)) { names.Add(Product.ConfigName); }

            foreach (string n in names)
            {
                string target = Path.Combine(dir, n);
                bool isConfig = n.EndsWith(".ini", StringComparison.OrdinalIgnoreCase);
                if (!File.Exists(target)) { continue; }
                if (isConfig && !removeConfig) { s.ConfigKept = true; Log.Line("config kept: " + target); continue; }
                if (Fs.TryDelete(target)) { s.FilesDeleted++; Log.Line("deleted " + target); }
                else { s.Leftovers.Add(target); Log.Line("could not delete " + target); }
            }
            Fs.TryDelete(manifest);
            Fs.RemoveLeftovers(dir);

            try
            {
                if (Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length == 0)
                {
                    Directory.Delete(dir, false);
                    s.FolderRemoved = true;
                    Log.Line("removed empty folder " + dir);
                }
            }
            catch (Exception ex) { Log.Line("folder not removed: " + ex.Message); }
            return s;
        }
    }

    internal sealed class ConfirmForm : Form
    {
        private readonly CheckBox config = new CheckBox();
        public bool RemoveConfig { get { return config.Checked; } }

        public ConfirmForm(string dir)
        {
            Text = Product.Name + " - Uninstall";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(480, 170);
            Font = SystemFonts.MessageBoxFont;

            Label text = new Label();
            text.Text = "Remove OpenInNvim from this computer?\r\n\r\nThe Explorer menu entries, the default-app entries and the files in\r\n" + dir + "\r\nare removed.";
            text.SetBounds(16, 14, 448, 80);
            Controls.Add(text);
            config.Text = "Also delete my settings (" + Product.ConfigName + ")";
            config.SetBounds(16, 100, 448, 22);
            Controls.Add(config);
            Button ok = new Button();
            ok.Text = "Uninstall";
            ok.SetBounds(292, 128, 84, 30);
            ok.DialogResult = DialogResult.OK;
            Controls.Add(ok);
            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.SetBounds(384, 128, 80, 30);
            cancel.DialogResult = DialogResult.Cancel;
            Controls.Add(cancel);
            AcceptButton = ok;
            CancelButton = cancel;
        }
    }

    internal static class UninstallProgram
    {
        [STAThread]
        private static int Main(string[] argv)
        {
            Args a = Args.Parse(argv);
            Log.Open(a.LogFile);
            try
            {
                string self = Process.GetCurrentProcess().MainModule.FileName;
                string dir = !string.IsNullOrEmpty(a.Dir) ? Fs.Normalize(a.Dir) : Path.GetDirectoryName(self);
                if (!a.Run) { return StageOne(a, self, dir); }
                return StageTwo(a, self, dir);
            }
            catch (Exception ex)
            {
                Log.Line("failed: " + ex);
                if (!a.Silent) { MessageBox.Show(ex.Message, Product.Name + " - Uninstall failed", MessageBoxButtons.OK, MessageBoxIcon.Error); }
                return 1;
            }
        }

        // Ask (unless silent), then hand over to a copy of this exe in %TEMP%.
        private static int StageOne(Args a, string self, string dir)
        {
            bool removeConfig = a.RemoveConfig;
            if (!a.Silent)
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (ConfirmForm f = new ConfirmForm(dir))
                {
                    if (f.ShowDialog() != DialogResult.OK) { return 2; }
                    removeConfig = removeConfig || f.RemoveConfig;
                }
            }
            string temp = Path.Combine(Path.GetTempPath(), "OpenInNvim-uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(self, temp, true);

            List<string> parts = new List<string>();
            parts.Add("/RUN");
            parts.Add("\"/DIR=" + dir + "\"");
            parts.Add("/PARENT=" + Process.GetCurrentProcess().Id);
            if (a.Silent) { parts.Add("/S"); }
            if (removeConfig) { parts.Add("/REMOVECONFIG"); }
            if (a.LogFile.Length > 0) { parts.Add("\"/LOG=" + a.LogFile + "\""); }
            if (a.Keys.Classes != new Keys().Classes) { parts.Add("\"/CLASSESKEY=" + a.Keys.Classes + "\""); }
            if (a.Keys.Software != new Keys().Software) { parts.Add("\"/SOFTWAREKEY=" + a.Keys.Software + "\""); }
            if (a.Keys.Uninstall != new Keys().Uninstall) { parts.Add("\"/UNINSTALLKEY=" + a.Keys.Uninstall + "\""); }

            ProcessStartInfo psi = new ProcessStartInfo(temp, string.Join(" ", parts.ToArray()));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process.Start(psi);
            Log.Line("handed over to " + temp);
            return 0;
        }

        private static int StageTwo(Args a, string self, string dir)
        {
            if (a.Parent > 0)
            {
                try { Process.GetProcessById(a.Parent).WaitForExit(15000); }
                catch (ArgumentException) { }   // already gone
                catch (InvalidOperationException) { }
            }
            UninstallSummary s = Uninstaller.Remove(a, dir, a.RemoveConfig);
            ScheduleSelfDelete(self);

            if (!a.Silent)
            {
                string msg = "OpenInNvim was removed.";
                if (s.ConfigKept) { msg += "\r\nYour settings (" + Product.ConfigName + ") were kept in " + dir + "."; }
                if (s.Leftovers.Count > 0) { msg += "\r\n\r\nCould not delete (still in use?):\r\n" + string.Join("\r\n", s.Leftovers.ToArray()); }
                MessageBox.Show(msg, Product.Name, MessageBoxButtons.OK, s.Leftovers.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
            }
            return s.Leftovers.Count > 0 ? 1 : 0;
        }

        // The temp copy is in use while it runs: a short-lived cmd.exe deletes it afterwards. The path is our
        // own (a GUID in %TEMP%), nothing user-supplied reaches the command line.
        private static void ScheduleSelfDelete(string self)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(
                    Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                    "/c ping -n 3 127.0.0.1 >nul & del /f /q \"" + self + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process.Start(psi);
            }
            catch (Exception ex) { Log.Line("self delete not scheduled: " + ex.Message); }
        }
    }
}
