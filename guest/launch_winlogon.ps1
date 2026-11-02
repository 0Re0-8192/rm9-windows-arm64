# run as SYSTEM: start a command line on the WINLOGON desktop of the console session (token of winlogon.exe duplicated) -> lets a script capture the logon screen
param([Parameter(Mandatory = $true)][string]$CommandLine)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WlLaunch {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
  [DllImport("advapi32.dll", SetLastError = true)] public static extern bool DuplicateTokenEx(IntPtr tok, uint access, IntPtr attr, int imp, int type, out IntPtr dup);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern bool CreateProcessAsUser(IntPtr token, string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  public static string Run(int winlogonPid, string cmd) {
    IntPtr hp = OpenProcess(0x1000 | 0x0400, false, winlogonPid);
    if (hp == IntPtr.Zero) return "OpenProcess failed " + Marshal.GetLastWin32Error();
    IntPtr tok; if (!OpenProcessToken(hp, 0x2 | 0x1 | 0x8 | 0x100 | 0x80 | 0x20, out tok)) return "OpenProcessToken failed " + Marshal.GetLastWin32Error();
    IntPtr dup; if (!DuplicateTokenEx(tok, 0xF01FF, IntPtr.Zero, 2, 1, out dup)) return "DuplicateTokenEx failed " + Marshal.GetLastWin32Error();
    STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si); si.lpDesktop = @"winsta0\winlogon";
    PROCESS_INFORMATION pi;
    bool ok = CreateProcessAsUser(dup, null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x400, IntPtr.Zero, null, ref si, out pi);
    uint ec = 0; if (ok) { WaitForSingleObject(pi.hProcess, 30000); GetExitCodeProcess(pi.hProcess, out ec); }
    return ok ? ("started pid " + pi.dwProcessId + " exit=0x" + ec.ToString("X")) : ("CreateProcessAsUser failed " + Marshal.GetLastWin32Error());
  }
}
'@
$wl = (Get-Process winlogon | Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1).Id
[WlLaunch]::Run($wl, $CommandLine)
