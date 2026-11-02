# Wrapper: run one Windows cycle with a fixed argument set, output to the file given as -Out (avoids shell quoting problems).
# -Touch: also write TOUCH.TXT (MuChain sets up the Goodix touch controller: SE4 clock, power, SMMU stream 0xA3) so that touchpoll.ps1 can start in Windows.
# -MuImage: Mu image to RAM-boot (default = the proven prod2 image).
param([string]$Out, [int]$CaptureWait = 420, [switch]$Devmode, [switch]$Touch, [switch]$Pcie, [string]$MuImage = '<RM9_WORKDIR>\out\Mu-fullrun-acpi_prod2.img')
$extra = @{}
if ($Touch) { $extra['Touch'] = $true }
if ($Pcie) { $extra['Pcie'] = $true }
& '<RM9_WORKDIR>\refs\phone_setup_loop.ps1' -Adsp -UsbFn -UsbPrep @extra -Max 1 -CaptureWait $CaptureWait -MuImage $MuImage *> $Out
