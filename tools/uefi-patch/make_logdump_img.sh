#!/bin/bash
# Wrap out/MuChain.efi (+ optional BRK.TXT RVAs) into the 64MB logdump FAT image.
# usage: make_logdump_img.sh ["1E06A8 1E06BC"]
set -e
RM9=<RM9_WORKDIR>
rm -f /root/muchain_esp.img; truncate -s 64M /root/muchain_esp.img
mkfs.vfat -F 32 -n MUESP /root/muchain_esp.img >/dev/null
mkdir -p /mnt/m && mount -o loop /root/muchain_esp.img /mnt/m
mkdir -p /mnt/m/EFI/BOOT
cp $RM9/out/MuChain.efi /mnt/m/EFI/BOOT/BOOTAA64.EFI
# "-" or empty = no breakpoints (an empty "" argument gets lost when called from PowerShell, so use "-")
if [ -n "$1" ] && [ "$1" != "-" ]; then printf '%s\n' "$1" > /mnt/m/BRK.TXT; fi
if [ "$2" = noboot ]; then echo 1 > /mnt/m/NOBOOT.TXT; fi
if [ -n "$ITSTEST" ]; then echo 1 > /mnt/m/ITSTEST.TXT; fi   # NOBOOT: standalone ITS/LPI delivery test (env var, no positional slot left)
if [ -n "$BHIVAR" ]; then echo 1 > /mnt/m/BHIVAR$BHIVAR.TXT; fi   # BHITEST variants of how the MSI write reaches the ITS: 1 = SMMU bypass for the stream, 2 = Android-like IOVA 0xA0000040 -> 0x17150040
if [ -n "$BHISINK" ]; then echo 1 > /mnt/m/BHISINK.TXT; fi   # BHITEST: point the endpoint's MSI at a DRAM page (does the chip raise an MSI at all?)
if [ -n "$BHITEST" ]; then echo 1 > /mnt/m/BHITEST.TXT; head -c 262144 $RM9/drivers/wcn7850_x/wlanfw20.mbn > /mnt/m/SBL.BIN; fi   # NOBOOT: PCIe up, the chip's BHI download raises a real MSI, ItsTest looks for the LPI (SBL.BIN = first 256 KB of the firmware, as Windows' BHI)
if [ "$3" = wptest ]; then echo 1 > /mnt/m/WPTEST.TXT; fi
if [ "$4" = nowp ]; then echo 1 > /mnt/m/NOWP.TXT; fi
if [ -n "$RM9_NOKEEP" ]; then echo 1 > /mnt/m/NOKEEP.TXT; fi
if [ -n "$RM9_NOCAP" ]; then echo 1 > /mnt/m/NOCAP.TXT; fi   # MuChain: leave the CPU clusters at the boot-time frequency   # LONGRUN without watchdog keep-alive (old behaviour: GH watchdog off at EBS)
if [ "$5" = longrun ]; then echo 1 > /mnt/m/LONGRUN.TXT; fi   # disable GH watchdog at EBS   # skip fPowerOnWPEn at EBS
if [ "$6" = disp ]; then echo 1 > /mnt/m/DISP.TXT; fi
if [ "$6" = refresh ]; then echo 1 > /mnt/m/REFRESH.TXT; fi   # MDP CTL_0 START every 30 ms (keeps the bootloader-configured panel pipe fed) until ExitBootServices   # start the stock DisplayDxe from MuChain
if [ "$7" = start0 ]; then echo 1 > /mnt/m/START0.TXT; fi   # MDP START probe at MuChain entry (no DisplayDxe)
if [ "$8" = usbfn ]; then echo 1 > /mnt/m/USBFN.TXT; fi   # set the dwc3 glue VBUS/session overrides before Windows (device mode)
if [ "$9" = usbdev ]; then echo 1 > /mnt/m/USBDEV.TXT; fi   # NOBOOT only: start the Qualcomm USB device stack towards the PC + golden register dump
if [ "${10}" = usbpwr ]; then echo 1 > /mnt/m/USBPWR.TXT; fi   # NOBOOT only: UsbPwrCtrlDxe protocol probe (read-only)
if [ "${11}" = vbuson ]; then echo 1 > /mnt/m/USBPWR1.TXT; fi   # also SetVbusEn(0,1) for 3 s
if [ "${12}" = adsp ]; then echo 1 > /mnt/m/ADSP.TXT; fi   # NOBOOT + USBPWR: load FULL_ADSP via PIL first
if [ "${13}" = ucsihost ]; then echo 1 > /mnt/m/UCSIHOST.TXT; fi   # UCSI SET_CCOM Rp-only after the ADSP is up (source/host)
if [ "${14}" = pmicraw ]; then echo 1 > /mnt/m/PMICRAW.TXT; fi
if [ "${15}" = rtr ]; then echo 1 > /mnt/m/RTR.TXT; fi
if [ "${16}" = windelay ]; then echo 1 > /mnt/m/WINDELAY.TXT; fi   # 180 s pause before Windows starts (swap the cable to an OTG device)
if [ "${18}" = touch ]; then echo 1 > /mnt/m/TOUCH.TXT; fi   # NOBOOT: Goodix touch bring-up probe over GENI SE4 SPI
case "${19}" in p0|p60|p90|p120) echo 1 > /mnt/m/PANEL.TXT;; esac   # DSI panel refresh-rate probe / switch (TE gpio86 measured before and after)
if [ "${19}" = p60 ]; then echo 1 > /mnt/m/PANEL60.TXT; fi
if [ "${19}" = p90 ]; then echo 1 > /mnt/m/PANEL90.TXT; fi
if [ "${19}" = p120 ]; then echo 1 > /mnt/m/PANEL120.TXT; fi
if [ "${20}" = usbreplay ]; then echo 1 > /mnt/m/USBREPLAY.TXT; fi   # NOBOOT: replay of Android's USB device-mode bring-up
if [ "${22}" = pcie ]; then echo 1 > /mnt/m/PCIE.TXT; fi   # normal boot: bring up PCIe0 + WCN7850 (Wi-Fi) before Windows and leave the link up
if [ "${21}" = usbprep ]; then echo 1 > /mnt/m/USBPREP.TXT; fi   # normal boot: bring the USB PHYs up before Windows (function-role experiments)
if [ "${17}" = ucsiinit ]; then echo 1 > /mnt/m/UCSIINIT.TXT; fi   # AdspLoad: only the UCSI init (reset + notifications), no probing
if [ "$2" != noboot ]; then echo 1 > /mnt/m/BOOTOK.TXT; fi   # explicit opt-in to start bootmgfw
sync -f /mnt/m; umount /mnt/m
cp /root/muchain_esp.img $RM9/winboot/muchain_esp.img
sha256sum /root/muchain_esp.img