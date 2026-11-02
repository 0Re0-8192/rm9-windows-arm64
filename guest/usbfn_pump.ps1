# S:\rm9\usbfn_pump.ps1 (SYSTEM): GenericUSBFn data experiment.  Opens the interface, ACTIVATE_USB_BUS, queries pipe info with pipe ids as IOCTL input, then runs one reader thread (TRANSFER_OUT) and one writer thread
# (TRANSFER_IN) per pipe id 1..3, logging every result (write-through): C:\rm9\session\fnpump.txt.   PC side: refs\pc_usbpump.py (writes to ep 0x01, reads from ep 0x81).
param([int]$Seconds = 400, [string]$Guid = '{7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b}')
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Pump {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
  static string LogPath = @"C:\rm9\session\fnpump.txt";
  static object Lk = new object();
  public static void L(string m) {
    lock (Lk) {
      using (FileStream fs = new FileStream(LogPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite, 4096, FileOptions.WriteThrough)) {
        byte[] b = Encoding.ASCII.GetBytes(DateTime.Now.ToString("HH:mm:ss.ff") + " " + m + "\r\n"); fs.Write(b, 0, b.Length);
      }
    }
  }
  static string Hex(byte[] b, int n) { StringBuilder sb = new StringBuilder(); for (int i = 0; i < n && i < b.Length; i++) sb.Append(b[i].ToString("X2")).Append(' '); return sb.ToString(); }
  const uint GET_CLASS_INFO = 0x22C022, GET_PIPE_STATE = 0x22C026, GET_IFDESC = 0x22C03E, ACTIVATE = 0x22C02C, XFER_IN = 0x22C00D, XFER_OUT = 0x22C016;
  static SafeFileHandle Open(string p) { return CreateFileW(p, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); }
  static void Query(SafeFileHandle h, string name, uint code, byte[] inb) {
    byte[] o = new byte[1024]; int r;
    bool ok = DeviceIoControl(h, code, inb, inb == null ? 0 : inb.Length, o, o.Length, out r, IntPtr.Zero);
    L(name + " in=" + (inb == null ? "-" : Hex(inb, 16)) + " ok=" + ok + " err=" + Marshal.GetLastWin32Error() + " bytes=" + r + " : " + Hex(o, Math.Min(r > 0 ? r : 32, 64)));
  }
  public static void Run(string path, int seconds) {
    SafeFileHandle h = Open(path);
    if (h.IsInvalid) { L("open failed " + Marshal.GetLastWin32Error()); return; }
    int r;
    bool ok = DeviceIoControl(h, ACTIVATE, null, 0, null, 0, out r, IntPtr.Zero);
    L("ACTIVATE ok=" + ok + " err=" + Marshal.GetLastWin32Error());
    Query(h, "GET_CLASS_INFO", GET_CLASS_INFO, null);
    for (uint pid = 0; pid <= 4; pid++) {
      byte[] pin = BitConverter.GetBytes(pid);
      Query(h, "GET_PIPE_STATE", GET_PIPE_STATE, pin);
    }
    Query(h, "GET_IFDESC", GET_IFDESC, BitConverter.GetBytes((uint)0));
    Thread te = new Thread(delegate() {
      SafeFileHandle he = Open(path); byte[] ev = new byte[64]; int n;
      for (;;) {
        bool k = DeviceIoControl(he, 0x22C036, null, 0, ev, ev.Length, out n, IntPtr.Zero);
        L("BUS_EVENT ok=" + k + " err=" + Marshal.GetLastWin32Error() + " bytes=" + n + " : " + Hex(ev, 16));
        if (!k) Thread.Sleep(1000);
      }
    });
    te.IsBackground = true; te.Start();
    foreach (uint pid in new uint[] { 0x01, 0x11 }) {
      uint p = pid;
      Query(h, "GET_PIPE_STATE 0x" + p.ToString("X"), GET_PIPE_STATE, BitConverter.GetBytes(p));
      Thread tr = new Thread(delegate() {
        SafeFileHandle hp = Open(path);
        byte[] pin = BitConverter.GetBytes(p); byte[] buf = new byte[512]; int n; int lastErr = -1;
        for (;;) {
          bool k = DeviceIoControl(hp, XFER_OUT, pin, 4, buf, buf.Length, out n, IntPtr.Zero);
          int e = Marshal.GetLastWin32Error();
          if (k) { L("pipe 0x" + p.ToString("X") + " OUT ok bytes=" + n + " : " + Hex(buf, Math.Min(n, 48))); lastErr = -1; }
          else { if (e != lastErr) L("pipe 0x" + p.ToString("X") + " OUT failed err=" + e); lastErr = e; Thread.Sleep(500); }
        }
      });
      tr.IsBackground = true; tr.Start();
      Thread tw = new Thread(delegate() {
        SafeFileHandle hp = Open(path);
        byte[] pin = BitConverter.GetBytes(p); int n; int cnt = 0, lastErr = -1;
        for (;;) {
          byte[] data = Encoding.ASCII.GetBytes("phone->PC pipe 0x" + p.ToString("X") + " #" + (cnt++));
          bool k = DeviceIoControl(hp, XFER_IN, pin, 4, data, data.Length, out n, IntPtr.Zero);
          int e = Marshal.GetLastWin32Error();
          if (k) { L("pipe 0x" + p.ToString("X") + " IN ok bytes=" + n); lastErr = -1; Thread.Sleep(1000); }
          else { if (e != lastErr) L("pipe 0x" + p.ToString("X") + " IN failed err=" + e); lastErr = e; Thread.Sleep(500); }
        }
      });
      tw.IsBackground = true; tw.Start();
    }
    Thread.Sleep(seconds * 1000);
    L("done");
  }
}
'@
function FindPath {
    $path = $null
    $bs = [string][char]92
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses' -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'USBFN' } | ForEach-Object { $path = ($bs + $bs + '?' + $bs + $_.PSChildName.Substring(4)) }
    }
    $path
}
New-Item -ItemType Directory -Force C:\rm9\session | Out-Null
$path = $null
for ($i = 0; $i -lt 30 -and -not $path; $i++) { $path = FindPath; if (-not $path) { Start-Sleep 2 } }
[Pump]::L("interface path: $path")
if ($path) { [Pump]::Run($path, $Seconds) }
