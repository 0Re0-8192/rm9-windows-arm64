# S:\rm9\launch_in_session.ps1 - run as SYSTEM: start a command line in the interactive console session (WTSQueryUserToken + CreateProcessAsUser)
param([Parameter(Mandatory = $true)][string]$CommandLine)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SessLaunch {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll")] public static extern int WTSGetActiveConsoleSessionId();
  [DllImport("wtsapi32.dll", SetLastError = true)] public static extern bool WTSQueryUserToken(int sessionId, out IntPtr token);
  [DllImport("userenv.dll", SetLastError = true)] public static extern bool CreateEnvironmentBlock(out IntPtr env, IntPtr token, bool inherit);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern bool CreateProcessAsUser(IntPtr token, string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  public static string Run(string cmd) {
    int sid = WTSGetActiveConsoleSessionId();
    IntPtr tok; if (!WTSQueryUserToken(sid, out tok)) return "WTSQueryUserToken failed " + Marshal.GetLastWin32Error() + " session " + sid;
    IntPtr env; CreateEnvironmentBlock(out env, tok, false);
    STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si); si.lpDesktop = @"winsta0\default";
    PROCESS_INFORMATION pi;
    bool ok = CreateProcessAsUser(tok, null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x400, env, null, ref si, out pi);
    uint ec = 0; if (ok) { WaitForSingleObject(pi.hProcess, 20000); GetExitCodeProcess(pi.hProcess, out ec); }
    return ok ? ("started pid " + pi.dwProcessId + " in session " + sid + " exit=0x" + ec.ToString("X")) : ("CreateProcessAsUser failed " + Marshal.GetLastWin32Error());
  }
}
'@
[SessLaunch]::Run($CommandLine)
