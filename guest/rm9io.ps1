# S:\rm9\rm9io.ps1 - user-mode client for rm9io.sys (physical MMIO read / write).  Dot-source it:   . S:\rm9\rm9io.ps1
#   Rm9Read  0xA60C120 [count]            -> array of UINT32
#   Rm9Write 0xA6F8810 0x10100000 [mask]  -> plain write (mask 0) or read-modify-write of the mask bits
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Rm9Io {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
  public static SafeFileHandle H;
  public static bool Open() {
    if (H != null && !H.IsInvalid && !H.IsClosed) return true;
    H = CreateFileW("\\\\.\\rm9io", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    return !H.IsInvalid;
  }
  public static uint[] Read(ulong phys, uint count) {
    byte[] inb = new byte[12];
    BitConverter.GetBytes(phys).CopyTo(inb, 0); BitConverter.GetBytes(count).CopyTo(inb, 8);
    byte[] outb = new byte[count * 4]; int ret;
    if (!DeviceIoControl(H, 0x8F002000, inb, inb.Length, outb, outb.Length, out ret, IntPtr.Zero))
      throw new Exception("Rm9Read failed, win32 error " + Marshal.GetLastWin32Error() + " at 0x" + phys.ToString("X"));
    uint[] r = new uint[count]; Buffer.BlockCopy(outb, 0, r, 0, (int)count * 4); return r;
  }
  public static void Write(ulong phys, uint val, uint mask) {
    byte[] inb = new byte[16];
    BitConverter.GetBytes(phys).CopyTo(inb, 0); BitConverter.GetBytes(val).CopyTo(inb, 8); BitConverter.GetBytes(mask).CopyTo(inb, 12);
    int ret;
    if (!DeviceIoControl(H, 0x8F002004, inb, inb.Length, null, 0, out ret, IntPtr.Zero))
      throw new Exception("Rm9Write failed, win32 error " + Marshal.GetLastWin32Error() + " at 0x" + phys.ToString("X"));
  }
}
'@
function Rm9Open { if (-not [Rm9Io]::Open()) { throw "cannot open \\.\rm9io (driver not loaded?)" } }
function Rm9Read([uint64]$Phys, [uint32]$Count = 1) { Rm9Open; [Rm9Io]::Read($Phys, $Count) }
function Rm9Write([uint64]$Phys, [uint32]$Value, [uint32]$Mask = 0) { Rm9Open; [Rm9Io]::Write($Phys, $Value, $Mask) }
function Rm9Dump([uint64]$Phys, [uint32]$Count = 16, [string]$Label = '') {
    $v = Rm9Read $Phys $Count
    for ($i = 0; $i -lt $Count; $i += 4) {
        $line = ('{0:X9} {1}' -f ($Phys + 4 * $i), $Label)
        for ($j = $i; $j -lt [Math]::Min($i + 4, $Count); $j++) { $line += (' {0:X8}' -f $v[$j]) }
        $line
    }
}
