# SYSTEM: send relative mouse reports (no report id) through the virtual HID device (A/B test of the VHF path; build rm9hid with RM9_MINI_DESC); the cursor position is read from the user session by cursorpos.ps1
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class MT {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool DeviceIoControl(SafeFileHandle h, uint c, byte[] i, int il, byte[] o, int ol, out int r, IntPtr ov);
  public static int Run() {
    SafeFileHandle h = CreateFileW(@"\\.\Rm9Hid", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); if (h.IsInvalid) return -Marshal.GetLastWin32Error();
    int err = 0; for (int i = 0; i < 40; i++) { int r; byte[] rpt = new byte[] { 0, 10, 10 }; if (!DeviceIoControl(h, 0x22A400, rpt, 3, null, 0, out r, IntPtr.Zero)) err = Marshal.GetLastWin32Error(); System.Threading.Thread.Sleep(10); }
    return err;
  }
}
'@
"mouse reports sent, last error = " + [MT]::Run()
