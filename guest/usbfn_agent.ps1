# usbfn_agent.ps1 (SYSTEM on the phone): remote-control agent over the GenericUSBFn bulk pipes (OUT=0x01 from the PC, IN=0x11 to the PC).
# Protocol (see refs/rm9link.py): every transfer is one frame:  magic u16 (0x5239) | type u8 | flags u8 | id u32 | plen u32 | payload   (little endian, 12-byte header)
#   PC->phone: 1 PING(echo)  2 EXEC("timeoutSec\ncmd")  3 PUT(flags bit0=truncate; u16 pathlen, path, data)  4 GET(path)  5 REBOOT  6 VER
#   phone->PC: 0x81 PONG  0x82 EXEC out chunk  0x83 EXEC done(int32 exit)  0x80 ACK(int32 status + text)  0x84 GET chunk  0x85 GET end(u64 size)  0x8F ERR(text)
# On the USB transport a frame whose length is a multiple of 512 gets one pad byte (no zero-length packets needed); receivers honour the header length.
# -Tcp <port>: test mode on the PC (loopback socket instead of USB, no padding).  Log (write-through): C:\rm9\session\agent.txt  (-Log to change)
param([int]$Seconds = 400, [string]$Guid = '{7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b}', [int]$Tcp = 0, [string]$Log = 'C:\rm9\session\agent.txt')
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public interface ITransport { byte[] Recv(); void Send(byte[] frame); }

public static class Dbg {
  public static string LogPath = @"C:\rm9\session\agent.txt";
  static object Lk = new object();
  public static void L(string m) {
    lock (Lk) {
      try {
        using (FileStream fs = new FileStream(LogPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite, 4096, FileOptions.WriteThrough)) {
          byte[] b = Encoding.UTF8.GetBytes(DateTime.Now.ToString("HH:mm:ss.ff") + " " + m + "\r\n"); fs.Write(b, 0, b.Length);
        }
      } catch (Exception) { }
    }
  }
}

public class TcpTransport : ITransport {
  NetworkStream s; TcpClient c;
  public TcpTransport(int port) {
    TcpListener l = new TcpListener(IPAddress.Loopback, port); l.Start();
    Dbg.L("tcp listening " + port);
    c = l.AcceptTcpClient(); s = c.GetStream(); l.Stop();
  }
  bool ReadN(byte[] b, int n) { int o = 0; while (o < n) { int r = s.Read(b, o, n - o); if (r <= 0) return false; o += r; } return true; }
  public byte[] Recv() {
    byte[] h = new byte[12]; if (!ReadN(h, 12)) return null;
    int plen = BitConverter.ToInt32(h, 8); byte[] f = new byte[12 + plen]; Array.Copy(h, f, 12);
    byte[] p = new byte[plen]; if (plen > 0) { if (!ReadN(p, plen)) return null; Array.Copy(p, 0, f, 12, plen); }
    return f;
  }
  public void Send(byte[] f) { s.Write(f, 0, f.Length); s.Flush(); }
}

public class UsbTransport : ITransport {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
  const uint ACTIVATE = 0x22C02C, XFER_IN = 0x22C00D, XFER_OUT = 0x22C016, BUS_EVENT = 0x22C036;
  SafeFileHandle hr, hw; string path;
  byte[] pOut = BitConverter.GetBytes((uint)0x01), pIn = BitConverter.GetBytes((uint)0x11);
  byte[] rbuf = new byte[65536];
  static SafeFileHandle Open(string p) { return CreateFileW(p, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); }
  public UsbTransport(string p, bool activate) {
    path = p;
    SafeFileHandle h = Open(p);
    if (h.IsInvalid) throw new Exception("open failed " + Marshal.GetLastWin32Error());
    int r;
    if (activate) { bool ok = DeviceIoControl(h, ACTIVATE, null, 0, null, 0, out r, IntPtr.Zero); Dbg.L("ACTIVATE ok=" + ok + " err=" + Marshal.GetLastWin32Error()); }
    // keep h open for the whole run (the bus stays active only while this handle is open)
    GC.KeepAlive(h); keep = h;
    hr = Open(p); hw = Open(p);
    Thread te = new Thread(delegate() {
      SafeFileHandle he = Open(path); byte[] ev = new byte[64]; int n;
      for (;;) {
        bool k = DeviceIoControl(he, BUS_EVENT, null, 0, ev, ev.Length, out n, IntPtr.Zero);
        StringBuilder sb = new StringBuilder(); for (int i = 0; i < 16; i++) sb.Append(ev[i].ToString("X2")).Append(' ');
        Dbg.L("BUS_EVENT ok=" + k + " err=" + Marshal.GetLastWin32Error() + " : " + sb);
        if (!k) Thread.Sleep(1000);
      }
    });
    te.IsBackground = true; te.Start();
  }
  SafeFileHandle keep;
  public byte[] Recv() {
    int lastErr = -1;
    for (;;) {
      int n;
      bool k = DeviceIoControl(hr, XFER_OUT, pOut, 4, rbuf, rbuf.Length, out n, IntPtr.Zero);
      int e = Marshal.GetLastWin32Error();
      if (!k) { if (e != lastErr) Dbg.L("OUT failed err=" + e); lastErr = e; Thread.Sleep(300); continue; }
      lastErr = -1;
      if (n < 12) {
        // the byte count may not be reported: trust the header instead
        if (BitConverter.ToUInt16(rbuf, 0) == 0x5239) n = 12 + BitConverter.ToInt32(rbuf, 8); else { Dbg.L("OUT short/garbage n=" + n); continue; }
      }
      if (BitConverter.ToUInt16(rbuf, 0) != 0x5239) { Dbg.L("OUT bad magic n=" + n); continue; }
      int plen = BitConverter.ToInt32(rbuf, 8);
      if (plen < 0 || 12 + plen > rbuf.Length) { Dbg.L("OUT bad plen " + plen); continue; }
      byte[] f = new byte[12 + plen]; Array.Copy(rbuf, f, f.Length); return f;
    }
  }
  public void Send(byte[] f) {
    byte[] d = f;
    if (f.Length % 512 == 0) { d = new byte[f.Length + 1]; Array.Copy(f, d, f.Length); }
    int lastErr = -1;
    for (;;) {
      int n;
      bool k = DeviceIoControl(hw, XFER_IN, pIn, 4, d, d.Length, out n, IntPtr.Zero);
      int e = Marshal.GetLastWin32Error();
      if (k) return;
      if (e != lastErr) Dbg.L("IN failed err=" + e);
      lastErr = e; Thread.Sleep(300);
    }
  }
}

// IP packets over the link: Wintun virtual adapter "rm9usb" on the phone; PC->phone frames type 0x11, phone->PC frames type 0x91 (id 0).  Needs C:\rm9\link\wintun.dll (arm64).
public static class PktNet {
  const string Dll = @"C:\rm9\link\wintun.dll";
  [DllImport(Dll, CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr WintunCreateAdapter(string name, string type, ref Guid g);
  [DllImport(Dll, SetLastError = true)] static extern IntPtr WintunStartSession(IntPtr a, uint cap);
  [DllImport(Dll)] static extern IntPtr WintunGetReadWaitEvent(IntPtr s);
  [DllImport(Dll, SetLastError = true)] static extern IntPtr WintunReceivePacket(IntPtr s, out uint size);
  [DllImport(Dll)] static extern void WintunReleaseReceivePacket(IntPtr s, IntPtr p);
  [DllImport(Dll, SetLastError = true)] static extern IntPtr WintunAllocateSendPacket(IntPtr s, uint size);
  [DllImport(Dll)] static extern void WintunSendPacket(IntPtr s, IntPtr p);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  static IntPtr sess = IntPtr.Zero;
  public static long TxPk = 0, RxPk = 0;
  public static void Start() {
    if (!File.Exists(@"C:\rm9\link\wintun.dll")) { Dbg.L("net: wintun.dll missing"); return; }
    Guid g = new Guid("5d6f0a1e-7c33-4b0f-9f55-2f6b1c0d9a42");
    IntPtr ad = WintunCreateAdapter("rm9usb", "RM9", ref g);
    if (ad == IntPtr.Zero) { Dbg.L("net: CreateAdapter failed " + Marshal.GetLastWin32Error()); return; }
    sess = WintunStartSession(ad, 0x400000);
    if (sess == IntPtr.Zero) { Dbg.L("net: StartSession failed " + Marshal.GetLastWin32Error()); return; }
    Dbg.L("net: adapter rm9usb up");
    Thread hb = new Thread(delegate() { for (;;) { Thread.Sleep(2000); try { Agent.PutRaw(0, 0x92, new byte[0]); } catch (Exception) { } } });
    hb.IsBackground = true; hb.Start();

    try {
      Process.Start("cmd.exe", "/c netsh interface ip set address name=rm9usb static 192.168.x.x 255.255.255.0 192.168.x.x & netsh interface ip set dnsservers name=rm9usb static 1.1.1.1 primary validate=no & netsh interface ipv4 set subinterface rm9usb mtu=14000 store=active");
    } catch (Exception ex) { Dbg.L("net: netsh " + ex.Message); }
    Thread t = new Thread(delegate() {
      IntPtr ev = WintunGetReadWaitEvent(sess);
      for (;;) {
        uint n; IntPtr p = WintunReceivePacket(sess, out n);
        if (p == IntPtr.Zero) { WaitForSingleObject(ev, 500); continue; }
        byte[] b = new byte[n]; Marshal.Copy(p, b, 0, (int)n); WintunReleaseReceivePacket(sess, p);
        if (n <= 15000) { try { Agent.PutRaw(0, 0x91, b); TxPk++; } catch (Exception) { } }
      }
    });
    t.IsBackground = true; t.Start();
  }
  public static void Inject(byte[] pkt) {
    if (sess == IntPtr.Zero) return;
    IntPtr p = WintunAllocateSendPacket(sess, (uint)pkt.Length);
    if (p == IntPtr.Zero) return;
    Marshal.Copy(pkt, 0, p, pkt.Length); WintunSendPacket(sess, p); RxPk++;
  }
}

public static class Agent {
  const int MaxData = 16000;
  static ITransport T;
  static object SendLk = new object();
  public static void PutRaw(uint id, byte type, byte[] payload) { Put(id, type, payload); }
  static void Put(uint id, byte type, byte[] payload) {
    byte[] f = new byte[12 + payload.Length];
    BitConverter.GetBytes((ushort)0x5239).CopyTo(f, 0); f[2] = type; f[3] = 0;
    BitConverter.GetBytes(id).CopyTo(f, 4); BitConverter.GetBytes(payload.Length).CopyTo(f, 8);
    Array.Copy(payload, 0, f, 12, payload.Length);
    lock (SendLk) { T.Send(f); }
  }
  static void Ack(uint id, int status, string text) {
    byte[] t = Encoding.UTF8.GetBytes(text == null ? "" : text); byte[] p = new byte[4 + t.Length];
    BitConverter.GetBytes(status).CopyTo(p, 0); Array.Copy(t, 0, p, 4, t.Length); Put(id, 0x80, p);
  }
  static void Err(uint id, string text) { Put(id, 0x8F, Encoding.UTF8.GetBytes(text)); }
  static void Exec(uint id, byte[] payload) {
    string s = Encoding.UTF8.GetString(payload); int nl = s.IndexOf('\n');
    int to = 60; string cmd = s;
    if (nl >= 0) { int.TryParse(s.Substring(0, nl).Trim(), out to); cmd = s.Substring(nl + 1); }
    if (to <= 0) to = 60;
    Dbg.L("EXEC (" + to + "s) " + cmd);
    ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c " + cmd);
    psi.UseShellExecute = false; psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true; psi.CreateNoWindow = true;
    MemoryStream ms = new MemoryStream(); int code;
    try {
      Process p = Process.Start(psi); p.StandardInput.Close();
      Thread t1 = new Thread(delegate() { CopyTo(p.StandardOutput.BaseStream, ms); }); t1.Start();
      Thread t2 = new Thread(delegate() { CopyTo(p.StandardError.BaseStream, ms); }); t2.Start();
      if (!p.WaitForExit(to * 1000)) {
        try { p.Kill(); } catch (Exception) { }
        byte[] m = Encoding.ASCII.GetBytes("\r\n[agent: timeout, killed]\r\n"); lock (ms) { ms.Write(m, 0, m.Length); }
        code = -1;
      } else code = p.ExitCode;
      t1.Join(3000); t2.Join(3000);
    } catch (Exception ex) { Err(id, "exec: " + ex.Message); return; }
    byte[] all; lock (ms) { all = ms.ToArray(); }
    for (int o = 0; o < all.Length; o += MaxData) {
      int n = Math.Min(MaxData, all.Length - o); byte[] c = new byte[n]; Array.Copy(all, o, c, 0, n); Put(id, 0x82, c);
    }
    Put(id, 0x83, BitConverter.GetBytes(code));
    Dbg.L("EXEC done exit=" + code + " out=" + all.Length);
  }
  static void CopyTo(Stream src, MemoryStream dst) {
    byte[] b = new byte[4096]; int n;
    try { while ((n = src.Read(b, 0, b.Length)) > 0) { lock (dst) { dst.Write(b, 0, n); } } } catch (Exception) { }
  }
  static void PutFile(uint id, byte flags, byte[] pl) {
    try {
      int pl2 = BitConverter.ToUInt16(pl, 0); string path = Encoding.UTF8.GetString(pl, 2, pl2);
      int off = 2 + pl2;
      string dir = Path.GetDirectoryName(path); if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
      using (FileStream fs = new FileStream(path, (flags & 1) != 0 ? FileMode.Create : FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) {
        fs.Write(pl, off, pl.Length - off);
      }
      Ack(id, 0, "");
    } catch (Exception ex) { Ack(id, 1, ex.Message); }
  }
  static void GetFile(uint id, byte[] pl) {
    string path = Encoding.UTF8.GetString(pl);
    try {
      long total = 0;
      using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
        byte[] b = new byte[MaxData]; int n;
        while ((n = fs.Read(b, 0, b.Length)) > 0) { byte[] c = new byte[n]; Array.Copy(b, c, n); Put(id, 0x84, c); total += n; }
      }
      Put(id, 0x85, BitConverter.GetBytes(total));
    } catch (Exception ex) { Err(id, ex.Message); }
  }
  public static void Serve(ITransport t, int seconds) {
    T = t; DateTime end = DateTime.Now.AddSeconds(seconds);
    Dbg.L("serving");
    try { PktNet.Start(); } catch (Exception ex) { Dbg.L("net start: " + ex.Message); }
    while (DateTime.Now < end) {
      byte[] f = T.Recv(); if (f == null) { Dbg.L("transport closed"); return; }
      byte type = f[2], flags = f[3]; uint id = BitConverter.ToUInt32(f, 4);
      byte[] pl = new byte[f.Length - 12]; Array.Copy(f, 12, pl, 0, pl.Length);
      if (type == 0x11) { PktNet.Inject(pl); continue; }
      Dbg.L("rx type=" + type + " id=" + id + " plen=" + pl.Length);
      try {
        switch (type) {
          case 1: Put(id, 0x81, pl); break;
          case 2: { uint eid = id; byte[] epl = pl; Thread et = new Thread(delegate() { try { Exec(eid, epl); } catch (Exception ex2) { Dbg.L("exec thread: " + ex2.Message); } }); et.IsBackground = true; et.Start(); break; }
          case 3: PutFile(id, flags, pl); break;
          case 4: GetFile(id, pl); break;
          case 5: Ack(id, 0, "rebooting"); Process.Start("cmd.exe", "/c shutdown /a & shutdown /r /t 2 /f"); break;
          case 6: Put(id, 0x81, Encoding.UTF8.GetBytes("rm9 agent v2 " + Environment.MachineName + " " + Environment.OSVersion.VersionString + " up=" + (Environment.TickCount / 1000) + "s net tx=" + PktNet.TxPk + " rx=" + PktNet.RxPk)); break;
          default: Err(id, "unknown type " + type); break;
        }
      } catch (Exception ex) { Dbg.L("handler exception " + ex); }
    }
    Dbg.L("serve time over");
  }
}
'@
[Dbg]::LogPath = $Log
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
function FindPath {
    $path = $null
    $bs = [string][char]92
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses' -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'USBFN' } | ForEach-Object { $path = ($bs + $bs + '?' + $bs + $_.PSChildName.Substring(4)) }
    }
    $path
}
[Dbg]::L("agent start tcp=$Tcp")
if ($Tcp -gt 0) {
    $until = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $until) { $t = New-Object TcpTransport($Tcp); [Agent]::Serve($t, [int]($until - (Get-Date)).TotalSeconds) }
    return
} else {
    $path = $null
    for ($i = 0; $i -lt 30 -and -not $path; $i++) { $path = FindPath; if (-not $path) { Start-Sleep 2 } }
    [Dbg]::L("interface path: $path")
    if (-not $path) { return }
    $t = New-Object UsbTransport($path, $true)
}
[Agent]::Serve($t, $Seconds)
