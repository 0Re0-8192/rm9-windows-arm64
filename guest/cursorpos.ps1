Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class CP{[StructLayout(LayoutKind.Sequential)]public struct P{public int x,y;}[DllImport("user32.dll")]public static extern bool GetCursorPos(out P p);}'
$p = New-Object CP+P; [void][CP]::GetCursorPos([ref]$p)
[IO.File]::AppendAllText('C:\rm9\link\cursor.txt', "$(Get-Date -Format HH:mm:ss) $($p.x),$($p.y)" + [Environment]::NewLine)
