# Turn off the touch contact ring and gesture visualization for the current user (live, via SystemParametersInfo)
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class Spi { [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, uint c, uint d); }'
# SPI_SETCONTACTVISUALIZATION 0x2019, SPI_SETGESTUREVISUALIZATION 0x201B; value 0 = off; 3 = save + broadcast
$r1 = [Spi]::SystemParametersInfo(0x2019, 0, 0, 3)
$r2 = [Spi]::SystemParametersInfo(0x201B, 0, 0, 3)
"contact=$r1 gesture=$r2" | Out-File C:\rm9\link\touchviz.txt -Encoding ascii
