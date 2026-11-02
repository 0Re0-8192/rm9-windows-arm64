#!/bin/bash
# Rebuild MuChain only and wrap it into the 64MB logdump FAT image.
set -e
RM9=<RM9_WORKDIR>
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg
sed -i 's/\r$//' $RM9/refs/MuChain.c $RM9/refs/MuChain.inf
cp $RM9/refs/MuChain.c $RM9/refs/MuChain.inf $P/Applications/MuChain/
if [ -n "$WDT_MS" ]; then sed -i "s/^#define WDT_MS .*/#define WDT_MS          $WDT_MS/" $P/Applications/MuChain/MuChain.c; fi
cd /root/Mu-Silicium
export CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
/root/.venv/bin/python3 build_uefi.py -d nx769j -r DEBUG > /root/muchain_build.log 2>&1 || { grep -E ' error: ' /root/muchain_build.log | cut -c1-260 | head -10; echo BUILD FAILED; exit 1; }
tail -2 /root/muchain_build.log
cp Build/nx769jPkg/DEBUG_CLANGPDB/AARCH64/MuChain.efi $RM9/out/MuChain.efi
bash $RM9/refs/make_logdump_img.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}" "${17}" "${18}" "${19}" "${20}" "${21}" "${22}"
ls -la $RM9/out/MuChain.efi
