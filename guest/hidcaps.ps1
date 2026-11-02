# SYSTEM: parse the virtual touch screen's HID descriptor with the Windows HID parser (what does Windows think the report looks like?) -> stdout
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HC {
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr p);
  [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
  [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr p, out CAPS c);
  [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref ATTR a);
  [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevsW(ref Guid g, IntPtr e, IntPtr h, uint f);
  [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i, ref IFACE o);
  [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr s, ref IFACE i, IntPtr d, uint n, out uint r, IntPtr dd);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [StructLayout(LayoutKind.Sequential)] struct IFACE { public uint cb; public Guid g; public uint fl; public IntPtr r; }
  [StructLayout(LayoutKind.Sequential)] struct ATTR { public uint size; public ushort vid, pid, ver; }
  [StructLayout(LayoutKind.Sequential)] struct CAPS { public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength; [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved; public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices, NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices, NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices; }
  public static string Run() {
    Guid g; HidD_GetHidGuid(out g);
    IntPtr set = SetupDiGetClassDevsW(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
    string res = "";
    for (uint i = 0; ; i++) {
      IFACE f = new IFACE(); f.cb = (uint)Marshal.SizeOf(typeof(IFACE));
      if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref f)) break;
      uint need; SetupDiGetDeviceInterfaceDetailW(set, ref f, IntPtr.Zero, 0, out need, IntPtr.Zero);
      IntPtr buf = Marshal.AllocHGlobal((int)need); Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
      if (!SetupDiGetDeviceInterfaceDetailW(set, ref f, buf, need, out need, IntPtr.Zero)) continue;
      string path = Marshal.PtrToStringUni(new IntPtr(buf.ToInt64() + 4));
      SafeFileHandle h = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
      if (h.IsInvalid) { res += path + " : cannot open (" + Marshal.GetLastWin32Error() + ")\r\n"; continue; }
      ATTR a = new ATTR(); a.size = (uint)Marshal.SizeOf(typeof(ATTR)); HidD_GetAttributes(h, ref a);
      if (a.vid != 0x1209) continue;
      IntPtr pp; CAPS c;
      if (HidD_GetPreparsedData(h, out pp)) {
        HidP_GetCaps(pp, out c);
        res += string.Format("{0}\r\n  vid={1:X4} pid={2:X4} usagePage=0x{3:X} usage=0x{4:X} in={5} out={6} feature={7} linkNodes={8} inBtn={9} inVal={10} featBtn={11} featVal={12}\r\n", path, a.vid, a.pid, c.UsagePage, c.Usage, c.InputReportByteLength, c.OutputReportByteLength, c.FeatureReportByteLength, c.NumberLinkCollectionNodes, c.NumberInputButtonCaps, c.NumberInputValueCaps, c.NumberFeatureButtonCaps, c.NumberFeatureValueCaps);
        HidD_FreePreparsedData(pp);
      } else res += path + " : no preparsed data\r\n";
    }
    return res;
  }
}
'@
[HC]::Run()
