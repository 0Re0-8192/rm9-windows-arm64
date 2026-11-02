# run in the console user's session: list the pointer devices Windows knows (GetPointerDevices) -> C:\rm9\link\pointerdev.txt
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PDev {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct POINTER_DEVICE_INFO { public uint displayOrientation; public IntPtr device; public int pointerDeviceType; public IntPtr monitor; public uint startingCursorId; public ushort maxActiveContacts; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 520)] public string productString; }
  [DllImport("user32.dll", SetLastError = true)] public static extern bool GetPointerDevices(ref uint count, [Out] POINTER_DEVICE_INFO[] d);
  public static string List() {
    uint n = 0; GetPointerDevices(ref n, null);
    POINTER_DEVICE_INFO[] d = new POINTER_DEVICE_INFO[n + 1]; n = (uint)d.Length; GetPointerDevices(ref n, d);
    string s = "count=" + n + "\r\n";
    for (int i = 0; i < n; i++) s += i + ": type=" + d[i].pointerDeviceType + " maxContacts=" + d[i].maxActiveContacts + " orient=" + d[i].displayOrientation + " product=" + d[i].productString + "\r\n";
    return s;
  }
}
'@
[IO.File]::WriteAllText('C:\rm9\link\pointerdev.txt', [PDev]::List())
