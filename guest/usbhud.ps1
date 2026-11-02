# C:\Users\Public\rm9shot\usbhud.ps1 - runs in the console user's session: full-screen topmost viewer of hud.txt (written by usbtest.ps1)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'; $f.TopMost = $true; $f.BackColor = [System.Drawing.Color]::Black
$l = New-Object System.Windows.Forms.Label
$l.Dock = 'Fill'; $l.ForeColor = [System.Drawing.Color]::Lime; $l.Font = New-Object System.Drawing.Font('Consolas', 15)
$l.Padding = New-Object System.Windows.Forms.Padding(12, 120, 12, 12)
$f.Controls.Add($l)
$tm = New-Object System.Windows.Forms.Timer
$tm.Interval = 2000
$tm.Add_Tick({ try { $l.Text = [IO.File]::ReadAllText('C:\Users\Public\rm9shot\hud.txt') } catch { $l.Text = 'waiting for hud.txt...' } })
$tm.Start()
[void]$f.ShowDialog()
