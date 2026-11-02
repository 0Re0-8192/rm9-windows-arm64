# C:\Users\Public\rm9shot\touchtest.ps1 - console-user session: full-screen black window that draws every mouse/touch event it receives as a dot (persistent trail) and logs it.
# Used to prove that InjectTouchInput (touchinject.ps1) really reaches the desktop; shot.ps1 screenshots show the trail.
param([int]$Seconds = 800)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$log = 'C:\Users\Public\rm9shot\mouse.log'
$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(0, 0)
$f.Size = [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize
$f.TopMost = $true; $f.BackColor = [System.Drawing.Color]::Black
$W = $f.Width; $H = $f.Height
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::DimGray), 3
$g.DrawRectangle($pen, 2, 2, $W - 5, $H - 5)
$g.DrawLine($pen, 0, 0, $W, $H); $g.DrawLine($pen, $W, 0, 0, $H)
$lime = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Lime)
$red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Red)
$font = New-Object System.Drawing.Font 'Consolas', 28
$script:n = 0
$f.Add_Paint({ param($s, $e) $e.Graphics.DrawImageUnscaled($bmp, 0, 0) })
$handler = {
    param($s, $e)
    $script:n++
    $b = if ($e.Button -ne 'None') { $lime } else { $red }
    $g.FillEllipse($b, $e.X - 12, $e.Y - 12, 24, 24)
    if ($script:n % 20 -eq 1) {
        $g.FillRectangle([System.Drawing.Brushes]::Black, 10, 10, 700, 50)
        $g.DrawString("n=$($script:n) x=$($e.X) y=$($e.Y)", $font, [System.Drawing.Brushes]::White, 10, 10)
    }
    Add-Content -Path $log -Value ("{0} {1} {2},{3} {4}" -f (Get-Date -Format 'HH:mm:ss.fff'), $e.Button, $e.X, $e.Y, $s.GetType().Name)
    $s.Invalidate()
}
$f.Add_MouseDown($handler); $f.Add_MouseMove($handler); $f.Add_MouseUp($handler)
$t = New-Object System.Windows.Forms.Timer
$t.Interval = $Seconds * 1000
$t.Add_Tick({ $f.Close() })
$t.Start()
Add-Content -Path $log -Value ("start {0}x{1}" -f $W, $H)
[void]$f.ShowDialog()
