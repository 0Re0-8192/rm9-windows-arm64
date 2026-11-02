# run in the console user's session: a small always-on-top, click-through counter at the top of the screen
#   physical taps  = touch.cur (what the touch controller reports): contact count 0 -> >=1
#   Windows clicks = low-level mouse hook: left button down / up (touch is promoted to mouse clicks)
#   Windows touch  = raw WM_POINTER DOWN/UP can not be seen from a click-through window, so the two numbers above are compared
# create C:\rm9\link\reset.txt to zero the counters
param([int]$Seconds = 3600)
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class TapForm : Form {
  delegate IntPtr HookProc(int code, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc p, IntPtr mod, uint tid);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
  static HookProc proc; static IntPtr hook;
  public static int Down, Up, PhysTaps, PhysFrames; static int lastCnt = 0; static string lastSeq = "";
  static DateTime lastDown = DateTime.MinValue; static double lastGap = 0;
  Label lbl = new Label(); Timer t = new Timer();
  public TapForm() {
    FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual; TopMost = true; ShowInTaskbar = false;
    Opacity = 0.80; BackColor = Color.Black; Location = new Point(0, 0); Size = new Size(1100, 230);
    lbl.Dock = DockStyle.Fill; lbl.ForeColor = Color.Lime; lbl.Font = new Font("Consolas", 26, FontStyle.Bold); lbl.TextAlign = ContentAlignment.MiddleLeft;
    Controls.Add(lbl);
    proc = Hook; hook = SetWindowsHookEx(14, proc, GetModuleHandle(null), 0);
    t.Interval = 40; t.Tick += (s, e) => Tick(); t.Start();
  }
  protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80 | 0x20 | 0x80000; return cp; } }
  protected override bool ShowWithoutActivation { get { return true; } }
  static IntPtr Hook(int code, IntPtr w, IntPtr l) {
    if (code >= 0) {
      int m = (int)w;
      if (m == 0x201) { Down++; DateTime n = DateTime.Now; lastGap = lastDown == DateTime.MinValue ? 0 : (n - lastDown).TotalMilliseconds; lastDown = n; }
      else if (m == 0x202) Up++;
    }
    return CallNextHookEx(hook, code, w, l);
  }
  void Tick() {
    try {
      if (File.Exists(@"C:\rm9\link\reset.txt")) { Down = Up = PhysTaps = PhysFrames = 0; lastCnt = 0; File.Delete(@"C:\rm9\link\reset.txt"); }
      string line = null;
      try { line = File.ReadAllText(@"C:\Users\Public\rm9shot\touch.cur"); } catch {}
      if (line != null && line.EndsWith(";")) {
        string[] p = line.Split(';');
        if (p[0] != lastSeq) {
          lastSeq = p[0]; int cnt = 0; int.TryParse(p[1], out cnt); PhysFrames++;
          if (cnt > 0 && lastCnt == 0) PhysTaps++;
          lastCnt = cnt;
        }
      }
    } catch {}
    lbl.Text = "PHYS taps (controller): " + PhysTaps + "\r\nWIN clicks down/up : " + Down + " / " + Up + "\r\nlast click gap     : " + (lastGap < 1 ? "-" : ((int)lastGap) + " ms");
  }
}
'@
$f = New-Object TapForm
$e = New-Object System.Windows.Forms.Timer; $e.Interval = $Seconds * 1000; $e.Add_Tick({ $f.Close() }); $e.Start()
[System.Windows.Forms.Application]::Run($f)
