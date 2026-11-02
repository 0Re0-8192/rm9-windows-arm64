# S:\rm9\usbfn_activate.ps1 - run as SYSTEM: open the GenericUSBFn device interface (InterfaceGUID from USBFN\Interfaces\GENERICUSBFN),
# send IOCTL_GENERICUSBFN_ACTIVATE_USB_BUS (0x0022C02C) so that UFX connects to the host, then keep the handle open and log.
param([string]$Guid = '{7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b}', [int]$Seconds = 150, [string]$Log = 'C:\rm9\session\activate.txt')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class UsbFnAct {
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
function L($m) { Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
$g = [Guid]$Guid
$paths = @()
for ($i = 0; $i -lt 15 -and $paths.Count -eq 0; $i++) {
    $p1 = [UsbFnAct]::FindPath($g); if ($p1) { $paths += $p1 }
    # whatever device interface the USBFN children registered, under any GUID
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses' -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'USBFN' } | ForEach-Object {
            L ("deviceclasses: " + $_.PSChildName)
            $bs = [string][char]92
            $paths += ($bs + $bs + '?' + $bs + $_.PSChildName.Substring(4))
        }
    }
    if ($paths.Count -eq 0) { Start-Sleep 2 }
}
L ("candidate interface paths: " + ($paths -join ' | '))
if ($paths.Count -eq 0) { L 'no interface (GenericUSBFn child not started?)'; return }
$handles = @()
foreach ($path in ($paths | Select-Object -Unique)) {
    $h = [UsbFnAct]::CreateFileW($path, [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) { L ("CreateFile failed " + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + " for $path"); continue }
    L "handle open: $path"
    $ret = 0
    $ok = [UsbFnAct]::DeviceIoControl($h, 0x0022C02C, $null, 0, $null, 0, [ref]$ret, [IntPtr]::Zero)
    L ("ACTIVATE_USB_BUS ok=$ok err=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + " for $path")
    $handles += $h
}
Start-Sleep -Seconds $Seconds
L 'done (closing handles)'
$handles | ForEach-Object { $_.Close() }
