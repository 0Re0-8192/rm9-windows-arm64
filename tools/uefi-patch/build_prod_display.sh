#!/bin/bash
# Production display image: Mu's SimpleFb GOP over the splash framebuffer + ClockDxe patched so the MDSS power survives (MuChain REFRESH.TXT then keeps START firing).
# All display debug hooks off.  usage: build_prod_display.sh <image name>
set -e
P=<RM9_WORKDIR>/refs
python3 $P/patch_stock_display.py 0
python3 $P/patch_fb_in_ramcon.py off
python3 $P/patch_sec_dispgolden.py off
python3 $P/patch_dxe_startprobe.py off
python3 $P/patch_ramcon_hwwatch.py off
python3 $P/patch_exc_trace.py off
python3 $P/patch_exc_dispdiag.py off
python3 $P/patch_efi_words.py /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/ClockDxe/ClockDxe.efi 0xa810=0x2A1F03E0
bash $P/build_acpi.sh "$1"
