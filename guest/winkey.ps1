# winkey.ps1 - run in the console session: press the Windows key (opens Start), wait, screenshot to C:\rm9\session\winkey_<n>.png.  -Text types a search string after Start opened.
param([string]$Text = '')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class K { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][K]::SetProcessDPIAware()
function Shot($name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save("C:\rm9\session\$name", [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}
New-Item -ItemType Directory -Force C:\rm9\session | Out-Null
[K]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [K]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Seconds 5
Shot 'winkey_1.png'
if ($Text) { [System.Windows.Forms.SendKeys]::SendWait($Text); Start-Sleep -Seconds 6; Shot 'winkey_2.png' }
Add-Content C:\rm9\session\winkey.txt ((Get-Date -Format 'HH:mm:ss') + ' done text=' + $Text)
