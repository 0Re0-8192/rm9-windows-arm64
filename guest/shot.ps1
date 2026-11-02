# S:\rm9\shot.ps1 - runs inside the interactive session of the console user (scheduled task rm9shot, AtLogOn): screenshot every 15 s to C:\rm9\session\shot_<n>.png (ring of 6) + screen geometry
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# DPI scaling is 150 %: without this the capture covers only the top-left 2/3 of the panel (taskbar missing)
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class DpiFix { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][DpiFix]::SetProcessDPIAware()
$dir = 'C:\rm9\session'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$n = 0
for ($i = 0; $i -lt 200; $i++) {
    try {
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save("$dir\shot_$($n % 6).png", [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Add-Content -Path "$dir\shots.txt" -Value ((Get-Date -Format 'HH:mm:ss') + " shot_$($n % 6).png ${($b.Width)}x$($b.Height) primary=$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width)x$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)")
        $n++
    } catch { Add-Content -Path "$dir\shots.txt" -Value ((Get-Date -Format 'HH:mm:ss') + ' ERR ' + $_.Exception.Message) }
    Start-Sleep -Seconds 15
}
