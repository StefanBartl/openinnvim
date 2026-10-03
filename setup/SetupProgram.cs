// OpenInNvim-Setup.exe: installs OpenInNvim for the current user, without administrator rights.
//
//   OpenInNvim-Setup.exe                      a small window (folder, default-app choice)
//   OpenInNvim-Setup.exe /S                   silent, defaults (folder of an earlier install, else
//                                             %LOCALAPPDATA%\OpenInNvim)
//   /D=<folder>  /DEFAULT=new|current  /NVIM=<nvim.exe>  /LOG=<file>
//
// The files are inside this exe (OpenInNvim.exe, uninstall.exe, the config template, two icons), so the
// repository is not needed. C# 5, ASCII only.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace OpenInNvimSetup
{
    internal sealed class InstallResult
    {
        public string Dir = "";
        public string NvimExe = "";
        public bool ConfigKept;
    }

    internal static class Installer
    {
        public static InstallResult Install(Args a, string dir, string defaultMode, string nvimGiven)
        {
            dir = Fs.Normalize(dir);
            if (Fs.IsRepository(dir)) { throw new ArgumentException("That folder is a git repository, choose another one: " + dir); }

            InstallResult result = new InstallResult();
            result.Dir = dir;

            string nvim = nvimGiven;
            if (string.IsNullOrEmpty(nvim)) { nvim = Nvim.Find(); }
            if (!string.IsNullOrEmpty(nvim) && !File.Exists(nvim)) { throw new ArgumentException("nvim.exe does not exist: " + nvim); }
            result.NvimExe = string.IsNullOrEmpty(nvim) ? "" : Path.GetFullPath(nvim);
            Log.Line("neovim: " + (result.NvimExe.Length > 0 ? result.NvimExe : "(not found)"));

            Directory.CreateDirectory(dir);
            Fs.RemoveLeftovers(dir);

            // 1) Files. The uninstaller goes first-class next to the launcher.
            Res.Extract(Product.ExeName, Path.Combine(dir, Product.ExeName));
            Res.Extract(Product.UninstallerName, Path.Combine(dir, Product.UninstallerName));
            Res.Extract(Product.NewIcon, Path.Combine(dir, Product.NewIcon));
            Res.Extract(Product.CurrentIcon, Path.Combine(dir, Product.CurrentIcon));
            Log.Line("files written to " + dir);

            foreach (string old in Product.OldFiles)
            {
                string p = Path.Combine(dir, old);
                if (File.Exists(p)) { Fs.TryDelete(p); Log.Line("removed old file " + p); }
            }

            // 2) Config: an existing one is yours and is kept.
            string config = Path.Combine(dir, Product.ConfigName);
            if (File.Exists(config))
            {
                result.ConfigKept = true;
                Log.Line("config kept: " + config);
            }
            else
            {
                string text = Res.ReadText(Product.ConfigName);
                if (result.NvimExe.Length > 0) { text = Ini.Set(text, "NVIM_BIN", result.NvimExe); }
                File.WriteAllText(config, text, new UTF8Encoding(false));
                Log.Line("config written: " + config);
            }

            // 3) The manifest lets uninstall.exe and uninstall.ps1 remove exactly these files.
            List<string> names = new List<string>(Product.Files);
            names.Add(Product.ConfigName);
            File.WriteAllLines(Path.Combine(dir, Product.ManifestName), names.ToArray());

            // 4) Registry.
            string exe = Path.Combine(dir, Product.ExeName);
            string icon = result.NvimExe.Length > 0 ? result.NvimExe : exe;
            Reg.WriteContextEntries(a.Keys, exe, icon);
            if (defaultMode == "new" || defaultMode == "current")
            {
                Reg.RegisterDefaultApp(a.Keys, defaultMode, exe, dir, Extensions.Read());
            }
            long size = 0;
            foreach (string n in names)
            {
                FileInfo fi = new FileInfo(Path.Combine(dir, n));
                if (fi.Exists) { size += fi.Length; }
            }
            Reg.WriteUninstallKey(a.Keys, dir, exe, size);
            Shell.AssocChanged(a.Keys);
            Log.Line("installed");
            return result;
        }

        public static string PreviousDir(Args a)
        {
            string prev = Reg.ReadInstallLocation(a.Keys);
            if (!string.IsNullOrEmpty(prev) && Directory.Exists(prev)) { return prev; }
            return Product.DefaultDir();
        }
    }

    internal sealed class SetupForm : Form
    {
        private readonly Args args;
        private readonly TextBox dirBox = new TextBox();
        private readonly RadioButton none = new RadioButton();
        private readonly RadioButton current = new RadioButton();
        private readonly RadioButton fresh = new RadioButton();
        private readonly Button install = new Button();
        public int ExitCode = 1;

        public SetupForm(Args a)
        {
            args = a;
            Text = Product.Name + " " + Product.Version() + " - Setup";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(520, 300);
            Font = SystemFonts.MessageBoxFont;

            Label title = new Label();
            title.Text = "Adds \"Open with Neovim (new instance)\" and \"(current instance)\" to the Explorer context menu.";
            title.SetBounds(16, 14, 488, 36);
            Controls.Add(title);

            Label dirLabel = new Label();
            dirLabel.Text = "Install folder:";
            dirLabel.SetBounds(16, 58, 488, 18);
            Controls.Add(dirLabel);
            dirBox.Text = !string.IsNullOrEmpty(a.Dir) ? a.Dir : Installer.PreviousDir(a);
            dirBox.SetBounds(16, 78, 400, 24);
            Controls.Add(dirBox);
            Button browse = new Button();
            browse.Text = "Browse...";
            browse.SetBounds(424, 76, 80, 28);
            browse.Click += delegate
            {
                using (FolderBrowserDialog d = new FolderBrowserDialog())
                {
                    d.Description = "Install folder";
                    if (d.ShowDialog(this) == DialogResult.OK) { dirBox.Text = d.SelectedPath; }
                }
            };
            Controls.Add(browse);

            string nvim = string.IsNullOrEmpty(a.Nvim) ? Nvim.Find() : a.Nvim;
            Label nvimLabel = new Label();
            nvimLabel.Text = nvim != null
                ? "Neovim found: " + nvim
                : "Neovim was not found. Set NVIM_BIN in the config file afterwards, or put nvim on PATH.";
            nvimLabel.SetBounds(16, 112, 488, 34);
            Controls.Add(nvimLabel);

            GroupBox box = new GroupBox();
            box.Text = "Default app for text files (Settings > Apps > Default apps)";
            box.SetBounds(16, 150, 488, 96);
            none.Text = "Do not register (context menu only)";
            none.Checked = true;
            none.SetBounds(14, 22, 440, 20);
            fresh.Text = "Register \"new instance\" as an option";
            fresh.SetBounds(14, 44, 440, 20);
            current.Text = "Register \"current instance\" as an option";
            current.SetBounds(14, 66, 440, 20);
            box.Controls.Add(none);
            box.Controls.Add(fresh);
            box.Controls.Add(current);
            Controls.Add(box);
            if (a.DefaultMode == "new") { fresh.Checked = true; }
            if (a.DefaultMode == "current") { current.Checked = true; }

            install.Text = "Install";
            install.SetBounds(332, 258, 84, 30);
            install.Click += OnInstall;
            Controls.Add(install);
            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.SetBounds(424, 258, 80, 30);
            cancel.Click += delegate { ExitCode = 2; Close(); };
            Controls.Add(cancel);
            AcceptButton = install;
            CancelButton = cancel;
        }

        private void OnInstall(object sender, EventArgs e)
        {
            install.Enabled = false;
            try
            {
                string mode = fresh.Checked ? "new" : (current.Checked ? "current" : "");
                InstallResult r = Installer.Install(args, dirBox.Text, mode, args.Nvim);
                string msg = "Installed to " + r.Dir + ".\r\n\r\n"
                    + "Right-click a file or folder in Explorer. On Windows 11 the entries are under \"Show more options\".\r\n"
                    + (r.ConfigKept ? "Your existing config was kept." : "Settings: " + Path.Combine(r.Dir, Product.ConfigName))
                    + "\r\n\r\nUninstall: Settings > Apps, or " + Path.Combine(r.Dir, Product.UninstallerName);
                if (r.NvimExe.Length == 0) { msg += "\r\n\r\nNeovim was not found: set NVIM_BIN in the config."; }
                MessageBox.Show(this, msg, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                ExitCode = 0;
                Close();
            }
            catch (Exception ex)
            {
                Log.Line("failed: " + ex);
                MessageBox.Show(this, ex.Message, Product.Name + " - Setup failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                install.Enabled = true;
            }
        }
    }

    internal static class SetupProgram
    {
        [STAThread]
        private static int Main(string[] argv)
        {
            Args a = Args.Parse(argv);
            Log.Open(a.LogFile);
            foreach (string u in a.Unknown) { Log.Line("ignored argument: " + u); }
            try
            {
                if (a.Silent)
                {
                    string dir = !string.IsNullOrEmpty(a.Dir) ? a.Dir : Installer.PreviousDir(a);
                    Installer.Install(a, dir, a.DefaultMode, a.Nvim);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (SetupForm f = new SetupForm(a))
                {
                    Application.Run(f);
                    return f.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Log.Line("failed: " + ex);
                if (!a.Silent)
                {
                    MessageBox.Show(ex.Message, Product.Name + " - Setup failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return 1;
            }
        }
    }
}
