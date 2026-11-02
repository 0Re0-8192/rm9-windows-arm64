# Touch-friendly launcher for the phone's Windows (the Start menu host crashes on this OS build).
# Run in the console user's session.  A small round "R9" button stays on top; tapping it opens/closes the panel with big buttons.
# The panel never takes focus from the app below (WS_EX_NOACTIVATE), so it is safe to leave running.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class R9Launcher : Form {
  Panel panel = new Panel(); Button toggle = new Button();
  public R9Launcher() {
    Rectangle sb = Screen.PrimaryScreen.Bounds;
    FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual; TopMost = true; ShowInTaskbar = false;
    BackColor = Color.Fuchsia; TransparencyKey = Color.Fuchsia;
    int bw = Math.Min(sb.Width / 2 - 20, 520), bh = 110, cols = 2;
    string[][] items = new string[][] {
      new string[]{"Explorer", "explorer.exe", ""},
      new string[]{"cmd", "cmd.exe", "/k cd /d C:\\"},
      new string[]{"PowerShell", "powershell.exe", "-NoExit"},
      new string[]{"Task Manager", "taskmgr.exe", ""},
      new string[]{"Notepad", "notepad.exe", ""},
      new string[]{"Run...", "rundll32.exe", "shell32.dll,#61"},
      new string[]{"Settings", "explorer.exe", "ms-settings:"},
      new string[]{"Restart", "shutdown.exe", "/r /t 3 /f"},
    };
    int rows = (items.Length + cols - 1) / cols;
    int pw = cols * (bw + 10) + 10, ph = rows * (bh + 10) + 10;
    panel.BackColor = Color.FromArgb(32, 32, 32); panel.Size = new Size(pw, ph); panel.Visible = false;
    for (int i = 0; i < items.Length; i++) {
      string[] it = items[i];
      Button b = new Button(); b.Text = it[0]; b.Font = new Font("Segoe UI", 22, FontStyle.Bold);
      b.ForeColor = Color.White; b.BackColor = it[0] == "Restart" ? Color.Firebrick : Color.FromArgb(0, 90, 160); b.FlatStyle = FlatStyle.Flat;
      b.Size = new Size(bw, bh); b.Location = new Point(10 + (i % cols) * (bw + 10), 10 + (i / cols) * (bh + 10));
      b.Click += (s, e) => { panel.Visible = false; Resize2(); try { Process.Start(it[1], it[2]); } catch (Exception) { } };
      panel.Controls.Add(b);
    }
    toggle.Text = "R9"; toggle.Font = new Font("Segoe UI", 20, FontStyle.Bold); toggle.Size = new Size(120, 120);
    toggle.ForeColor = Color.White; toggle.BackColor = Color.FromArgb(0, 120, 215); toggle.FlatStyle = FlatStyle.Flat;
    toggle.Click += (s, e) => { panel.Visible = !panel.Visible; Resize2(); };
    Controls.Add(panel); Controls.Add(toggle);
    Resize2();
  }
  void Resize2() {
    Rectangle sb = Screen.PrimaryScreen.Bounds;
    if (panel.Visible) {
      ClientSize = new Size(Math.Max(panel.Width, toggle.Width), panel.Height + toggle.Height + 10);
      toggle.Location = new Point(ClientSize.Width - toggle.Width, 0);
      panel.Location = new Point(0, toggle.Height + 10);
    } else {
      ClientSize = new Size(toggle.Width, toggle.Height); toggle.Location = new Point(0, 0);
    }
    Location = new Point(sb.Right - Width - 10, sb.Bottom - Height - 200);   // above the taskbar / gesture area
  }
  protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80; return cp; } }   // NOACTIVATE | TOOLWINDOW
  protected override bool ShowWithoutActivation { get { return true; } }
}
'@
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run((New-Object R9Launcher))
