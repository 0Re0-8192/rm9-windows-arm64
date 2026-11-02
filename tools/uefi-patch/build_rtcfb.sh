#!/bin/bash
# observation Mu: build_prod_display's patch set, but with the GOP framebuffer redirected into RAMCON (so the 640x680 SNAPs show what Windows/bootmgr draw), plus the real-date RTC
set -e
P=<RM9_WORKDIR>/refs
python3 $P/patch_rtc_date.py on 2026 10 20
python3 $P/patch_stock_display.py 0
python3 $P/patch_fb_in_ramcon.py on
python3 $P/patch_sec_dispgolden.py off
python3 $P/patch_dxe_startprobe.py off
python3 $P/patch_ramcon_hwwatch.py off
python3 $P/patch_exc_trace.py off
python3 $P/patch_exc_dispdiag.py off
python3 $P/patch_efi_words.py /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/ClockDxe/ClockDxe.efi 0xa810=0x2A1F03E0
bash $P/build_acpi.sh "$1"
