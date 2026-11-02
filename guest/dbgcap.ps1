# dbgcap.ps1 - user-mode client of dbgcap.sys (kernel DbgPrint capture + kernel virtual address reads).  Dot-source it.
#   DbgRead            -> new DbgPrint text since the last call
#   KModBase 'x.sys'   -> image base of a loaded kernel module (NtQuerySystemInformation)
#   KReadVa va len     -> bytes at a kernel virtual address (0xEE where not mapped)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DbgCap {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
  [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
  public static SafeFileHandle H;
  public static bool Open() {
    if (H != null && !H.IsInvalid && !H.IsClosed) return true;
    H = CreateFileW("\\\\.\\dbgcap", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    return !H.IsInvalid;
  }
  public static string Read() {
    if (!Open()) return "";
    byte[] outb = new byte[60000]; int ret;
    if (!DeviceIoControl(H, 0x8F002800, null, 0, outb, outb.Length, out ret, IntPtr.Zero)) return "";
    return System.Text.Encoding.ASCII.GetString(outb, 0, ret);
  }
  public static ulong ModuleBase(string name) {
    int ret; IntPtr buf = Marshal.AllocHGlobal(0x100000);
    try {
      if (NtQuerySystemInformation(11, buf, 0x100000, out ret) != 0) return 0;
      int count = Marshal.ReadInt32(buf);
      // RTL_PROCESS_MODULE_INFORMATION (64-bit): Section(8) MappedBase(8) ImageBase(8) ImageSize(4) Flags(4) 4 x USHORT, FullPathName[256] = 296 bytes; the list starts at +8
      for (int i = 0; i < count; i++) {
        IntPtr e = IntPtr.Add(buf, 8 + i * 296);
        string path = Marshal.PtrToStringAnsi(IntPtr.Add(e, 40));
        if (path != null && path.ToLower().EndsWith(name.ToLower())) return (ulong)Marshal.ReadInt64(e, 16);
      }
    } finally { Marshal.FreeHGlobal(buf); }
    return 0;
  }
  public static uint[] LpiTest(uint cpu, uint dev, uint ev, uint usec) {
    if (!Open()) return null;
    byte[] inb = new byte[16];
    BitConverter.GetBytes(cpu).CopyTo(inb, 0); BitConverter.GetBytes(dev).CopyTo(inb, 4); BitConverter.GetBytes(ev).CopyTo(inb, 8); BitConverter.GetBytes(usec).CopyTo(inb, 12);
    byte[] outb = new byte[88]; Array.Copy(inb, outb, 16); int ret;
    if (!DeviceIoControl(H, 0x8F002808, outb, 16, outb, 88, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[22]; Buffer.BlockCopy(outb, 0, r, 0, 88); return r;
  }
  public static uint[] ItsStorm(uint dev, uint ev, uint count) {
    if (!Open()) return null;
    byte[] outb = new byte[16];
    BitConverter.GetBytes(dev).CopyTo(outb, 0); BitConverter.GetBytes(ev).CopyTo(outb, 4); BitConverter.GetBytes(count).CopyTo(outb, 8);
    int ret;
    if (!DeviceIoControl(H, 0x8F00280C, outb, 12, outb, 16, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[4]; Buffer.BlockCopy(outb, 0, r, 0, 16); return r;
  }
  public static uint[] Hppir(uint cpu, uint mode, uint dev, uint ev, uint usec) {
    if (!Open()) return null;
    byte[] outb = new byte[64];
    BitConverter.GetBytes(cpu).CopyTo(outb, 0); BitConverter.GetBytes(mode).CopyTo(outb, 4); BitConverter.GetBytes(dev).CopyTo(outb, 8);
    BitConverter.GetBytes(ev).CopyTo(outb, 12); BitConverter.GetBytes(usec).CopyTo(outb, 16);
    int ret;
    if (!DeviceIoControl(H, 0x8F002810, outb, 20, outb, 64, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[16]; Buffer.BlockCopy(outb, 0, r, 0, 64); return r;
  }
  public static uint[] Gov(uint mode, uint arg) {
    if (!Open()) return null;
    byte[] b = new byte[208];
    BitConverter.GetBytes(mode).CopyTo(b, 0); BitConverter.GetBytes(arg).CopyTo(b, 4);
    int ret;
    if (!DeviceIoControl(H, 0x8F002828, b, 8, b, 208, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[52]; Buffer.BlockCopy(b, 0, r, 0, 208); return r;
  }
  public static uint[] Irq(uint mode, uint first, uint count, uint flags) {
    if (!Open()) return null;
    byte[] b = new byte[280];
    BitConverter.GetBytes(mode).CopyTo(b, 0); BitConverter.GetBytes(first).CopyTo(b, 4); BitConverter.GetBytes(count).CopyTo(b, 8); BitConverter.GetBytes(flags).CopyTo(b, 12);
    int ret;
    if (!DeviceIoControl(H, 0x8F002824, b, 16, b, 280, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[70]; Buffer.BlockCopy(b, 0, r, 0, 280); return r;
  }
  public static uint[] Timing() {
    if (!Open()) return null;
    byte[] outb = new byte[48]; int ret;
    if (!DeviceIoControl(H, 0x8F002814, null, 0, outb, 48, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[12]; Buffer.BlockCopy(outb, 0, r, 0, 48); return r;
  }
  public static uint[] Poll(ulong b, uint ms) {
    if (!Open()) return null;
    byte[] outb = new byte[16];
    BitConverter.GetBytes(b).CopyTo(outb, 0); BitConverter.GetBytes(ms).CopyTo(outb, 8);
    int ret;
    if (!DeviceIoControl(H, 0x8F002818, outb, 12, outb, 16, out ret, IntPtr.Zero)) return null;
    uint[] r = new uint[4]; Buffer.BlockCopy(outb, 0, r, 0, 16); return r;
  }
  public static byte[] Prev(uint off) {
    if (!Open()) return null;
    byte[] buf = new byte[65536 + 4]; int ret;
    BitConverter.GetBytes(off).CopyTo(buf, 0);
    if (!DeviceIoControl(H, 0x8F00281C, buf, 4, buf, buf.Length, out ret, IntPtr.Zero)) return null;
    byte[] r = new byte[ret]; Array.Copy(buf, r, ret); return r;
  }
  public static byte[] ReadVa(ulong va, int len) {
    if (!Open()) return null;
    byte[] inb = new byte[Math.Max(12, len)];
    BitConverter.GetBytes(va).CopyTo(inb, 0); BitConverter.GetBytes((uint)len).CopyTo(inb, 8);
    byte[] outb = new byte[len]; int ret;
    if (!DeviceIoControl(H, 0x8F002804, inb, 12, outb, len, out ret, IntPtr.Zero)) return null;
    return outb;
  }
}
'@
function DbgRead { [DbgCap]::Read() }
function KModBase([string]$n) { [DbgCap]::ModuleBase($n) }
function KReadVa([uint64]$va, [int]$len) { [DbgCap]::ReadVa($va, $len) }
function DbgLpiTest([uint32]$cpu, [uint32]$dev, [uint32]$ev, [uint32]$usec) { [DbgCap]::LpiTest($cpu, $dev, $ev, $usec) }
function DbgItsStorm([uint32]$dev, [uint32]$ev, [uint32]$count) { [DbgCap]::ItsStorm($dev, $ev, $count) }
function DbgHppir([uint32]$cpu, [uint32]$mode, [uint32]$dev, [uint32]$ev, [uint32]$usec) { [DbgCap]::Hppir($cpu, $mode, $dev, $ev, $usec) }
function DbgTiming { [DbgCap]::Timing() }
function DbgGov([uint32]$mode, [uint32]$arg) { [DbgCap]::Gov($mode, $arg) }
function DbgIrq([uint32]$mode, [uint32]$first, [uint32]$count, [uint32]$flags) { [DbgCap]::Irq($mode, $first, $count, $flags) }
function DbgPoll([uint64]$base, [uint32]$ms) { [DbgCap]::Poll($base, $ms) }
