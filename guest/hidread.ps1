# SYSTEM: open the virtual touch screen's HID collection for reading and count the input reports that arrive for -Seconds (run touchhid.ps1 -Test meanwhile)
param([int]$Seconds = 10)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;
public static class HR {
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref ATTR a);
  [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevsW(ref Guid g, IntPtr e, IntPtr h, uint f);
  [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i, ref IFACE o);
  [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr s, ref IFACE i, IntPtr d, uint n, out uint r, IntPtr dd);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadFile(SafeFileHandle h, byte[] b, uint n, out uint r, IntPtr ov);
  [StructLayout(LayoutKind.Sequential)] struct IFACE { public uint cb; public Guid g; public uint fl; public IntPtr r; }
  [StructLayout(LayoutKind.Sequential)] struct ATTR { public uint size; public ushort vid, pid, ver; }
  public static string Run(int seconds) {
    Guid g; HidD_GetHidGuid(out g);
    IntPtr set = SetupDiGetClassDevsW(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
    for (uint i = 0; ; i++) {
      IFACE f = new IFACE(); f.cb = (uint)Marshal.SizeOf(typeof(IFACE));
      if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref f)) break;
      uint need; SetupDiGetDeviceInterfaceDetailW(set, ref f, IntPtr.Zero, 0, out need, IntPtr.Zero);
      IntPtr buf = Marshal.AllocHGlobal((int)need); Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
      if (!SetupDiGetDeviceInterfaceDetailW(set, ref f, buf, need, out need, IntPtr.Zero)) continue;
      string path = Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
      SafeFileHandle h0 = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
      if (h0.IsInvalid) continue;
      ATTR a = new ATTR(); a.size = (uint)Marshal.SizeOf(typeof(ATTR)); HidD_GetAttributes(h0, ref a);
      if (a.vid != 0x1209) continue;
      SafeFileHandle h = CreateFileW(path, 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
      if (h.IsInvalid) return "open for read failed " + Marshal.GetLastWin32Error() + " (" + path + ")";
      int count = 0; string first = "";
      Thread t = new Thread(delegate() {
        byte[] b = new byte[16]; uint n;
        for (;;) { if (!ReadFile(h, b, 16, out n, IntPtr.Zero)) return; count++; if (count <= 3) first += BitConverter.ToString(b, 0, (int)n) + " | "; }
      });
      t.IsBackground = true; t.Start();
      Thread.Sleep(seconds * 1000);
      return "reports read: " + count + "  first: " + first;
    }
    return "device not found";
  }
}
'@
[HR]::Run($Seconds)
