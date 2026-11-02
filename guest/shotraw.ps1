# run in the console user's session: raw BGRA dump of the primary screen -> C:\rm9\link\shot.raw (+ shot.txt with the geometry)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$r = New-Object System.Drawing.Rectangle 0, 0, $b.Width, $b.Height
$d = $bmp.LockBits($r, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$buf = New-Object byte[] ($d.Stride * $b.Height)
[System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
$bmp.UnlockBits($d)
[IO.File]::WriteAllBytes('C:\rm9\link\shot.raw', $buf)
"$($b.Width)x$($b.Height) stride=$($d.Stride)" | Out-File C:\rm9\link\shot.txt -Encoding ascii
