#!/bin/bash
# boot_a for the slot-a Windows launcher: the Mu image + an AVB hash footer signed with the project's test key (same key/rollback as boot_b)
set -e
cd /root
mkdir -p slota && cd slota
cp <RM9_WORKDIR>/out/Mu-pcie-rp5.img boot_a_mu.img
python3 /mnt/d/Projects/nx769j-steam-kernel/tools/avbtool.py add_hash_footer --image boot_a_mu.img --partition_name boot --partition_size 100663296 --algorithm SHA256_RSA4096 --key /home/<user>/nx769j-steam-kernel/avb-test/testkey_rsa4096.pem --rollback_index 1706745600
python3 /mnt/d/Projects/nx769j-steam-kernel/tools/avbtool.py info_image --image boot_a_mu.img | head -20
ls -l boot_a_mu.img
sha256sum boot_a_mu.img
cp boot_a_mu.img <RM9_WORKDIR>/winboot/slota/boot_a_mu.img
