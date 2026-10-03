// Chooser.cs - the only windows this program ever shows: the instance list for INSTANCE_PICK = ask,
// and an error box when nothing can be started. WinForms is loaded on these paths only (each use
// sits in its own non-inlined method, so a normal click never touches the assembly).

using System;
using System.Drawing;
using System.Runtime.CompilerServices;
using System.Windows.Forms;

namespace OpenInNvim
{
    public static class Chooser
    {
        /// <summary>Index of the picked label, or -1 when the dialog was cancelled.</summary>
        public static int Pick(string[] labels, Hooks hooks)
        {
            // Tests pick without a window.
            if (hooks.PickIndex >= 0) { return hooks.PickIndex < labels.Length ? hooks.PickIndex : -1; }
            if (hooks.NoUi) { return 0; }
            return ShowList(labels);
        }

        public static void ShowError(string text, Hooks hooks)
        {
            if (hooks.NoUi) { return; }
            try { ShowBox(text); }
            catch (Exception ex) { Log.Line("message box failed: " + ex.Message); }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ShowBox(string text)
        {
            MessageBox.Show(text, "Open in Neovim", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int ShowList(string[] labels)
        {
            Application.EnableVisualStyles();
            int picked = -1;
            using (Form form = new Form())
            using (ListBox list = new ListBox())
            {
                form.Text = "Open in Neovim - choose instance";
                form.StartPosition = FormStartPosition.CenterScreen;
                form.TopMost = true;
                form.Width = 760;
                form.Height = 300;
                form.MinimizeBox = false;
                form.MaximizeBox = false;
                form.KeyPreview = true;

                list.Dock = DockStyle.Fill;
                list.Font = new Font("Consolas", 10f);
                list.IntegralHeight = false;
                for (int i = 0; i < labels.Length; i++) { list.Items.Add(labels[i]); }
                if (list.Items.Count > 0) { list.SelectedIndex = 0; }
                form.Controls.Add(list);

                list.DoubleClick += delegate
                {
                    if (list.SelectedIndex >= 0) { picked = list.SelectedIndex; form.Close(); }
                };
                form.KeyDown += delegate(object sender, KeyEventArgs e)
                {
                    if (e.KeyCode == Keys.Return && list.SelectedIndex >= 0) { picked = list.SelectedIndex; e.Handled = true; form.Close(); }
                    else if (e.KeyCode == Keys.Escape) { e.Handled = true; form.Close(); }
                };
                form.Shown += delegate { form.Activate(); list.Focus(); };
                form.ShowDialog();
            }
            return picked;
        }
    }
}
