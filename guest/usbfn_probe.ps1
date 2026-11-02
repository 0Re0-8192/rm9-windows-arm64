# S:\rm9\usbfn_probe.ps1 (SYSTEM): open the GenericUSBFn interface, ACTIVATE_USB_BUS, then find out how the pipes are used: GET_CLASS_INFO / GET_INTERFACE_DESCRIPTOR_SET (hex dump + parse),
# and try to open the pipe handles under several path spellings.  Log (write-through): C:\rm9\session\fnprobe.txt.   The handles stay open for -Seconds so that the function stays active.
param([int]$Seconds = 400, [string]$Guid = '{7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b}')
function Add-Content {
    param([Parameter(Position = 0)]$Path, [Parameter(Position = 1)]$Value)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes("$Value`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
$log = 'C:\rm9\session\fnprobe.txt'
function L($m) { Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss.ff'), $m) }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class Fn {
  [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] public static extern int CM_Get_Device_Interface_List_SizeW(out int len, ref Guid g, string dev, int flags);
  [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)] public static extern int CM_Get_Device_Interface_ListW(ref Guid g, string dev, StringBuilder buf, int len, int flags);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inl, byte[] outb, int outl, out int ret, IntPtr ov);
  public static string FindPath(Guid g) {
    int len; int cr = CM_Get_Device_Interface_List_SizeW(out len, ref g, null, 0);
    if (cr != 0 || len < 2) return null;
    StringBuilder sb = new StringBuilder(len);
    cr = CM_Get_Device_Interface_ListW(ref g, null, sb, len, 0);
    if (cr != 0) return null;
    string s = sb.ToString(); int z = s.IndexOf('\0'); return z > 0 ? s.Substring(0, z) : null;
  }
}
'@
function Hex([byte[]]$b, [int]$n) { (($b[0..([Math]::Min($n, $b.Length) - 1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') }
$g = [Guid]$Guid
$path = $null
for ($i = 0; $i -lt 30 -and -not $path; $i++) {
    $path = [Fn]::FindPath($g)
    if (-not $path) {
        # fallback (as usbfn_activate.ps1): the interface key under DeviceClasses, any GUID
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses' -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'USBFN' } | ForEach-Object {
                $bs = [string][char]92
                $path = ($bs + $bs + '?' + $bs + $_.PSChildName.Substring(4))
            }
        }
    }
    if (-not $path) { Start-Sleep 2 }
}
L "interface path: $path"
if (-not $path) { return }
$h = [Fn]::CreateFileW($path, 3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h.IsInvalid) { L ("CreateFile failed " + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); return }
$ret = 0
$ok = [Fn]::DeviceIoControl($h, 0x22C02C, $null, 0, $null, 0, [ref]$ret, [IntPtr]::Zero)
L ("ACTIVATE_USB_BUS ok=$ok err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
foreach ($c in @(@('GET_CLASS_INFO', 0x22C022), @('GET_CLASS_INFO_EX', 0x22C03A), @('GET_INTERFACE_DESCRIPTOR_SET', 0x22C03E), @('GET_PIPE_STATE', 0x22C026))) {
    $buf = New-Object byte[] 4096
    $ret = 0
    $ok = [Fn]::DeviceIoControl($h, $c[1], $null, 0, $buf, $buf.Length, [ref]$ret, [IntPtr]::Zero)
    L ("{0} (0x{1:X}) ok={2} err={3} bytes={4}: {5}" -f $c[0], $c[1], $ok, [Runtime.InteropServices.Marshal]::GetLastWin32Error(), $ret, $(if ($ret -gt 0) { Hex $buf ([Math]::Min($ret, 160)) } else { '' }))
}
# try to open pipes: path + suffix
foreach ($suf in @('\0', '\1', '\2', '\3', '\PIPE0', '\PIPE1', '\PIPE2', '\PIPE3', '\Pipe0', '\Pipe1', '\Pipe2', '/0', '/1', '/2', '#0', '#1', '#2')) {
    $ph = [Fn]::CreateFileW($path + $suf, 3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    L ("open pipe '{0}': {1} (err {2})" -f $suf, $(if ($ph.IsInvalid) { 'FAILED' } else { 'OK' }), $err)
    if (-not $ph.IsInvalid) {
        $buf = New-Object byte[] 256; $ret = 0
        $ok = [Fn]::DeviceIoControl($ph, 0x22C026, $null, 0, $buf, $buf.Length, [ref]$ret, [IntPtr]::Zero)
        L ("  GET_PIPE_STATE on it: ok=$ok err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + " bytes=$ret " + $(if ($ret -gt 0) { Hex $buf $ret } else { '' }))
        $ph.Close()
    }
}
L "holding the interface handle for $Seconds s"
Start-Sleep -Seconds $Seconds
L 'done'
$h.Close()
