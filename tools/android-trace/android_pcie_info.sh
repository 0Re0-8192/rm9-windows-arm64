#!/system/bin/sh
# run on the phone as root: PCIe0 / cnss state under Android
echo "== /dev/mem + pci-msm debugfs"
ls -la /dev/mem 2>&1
ls /sys/kernel/debug/pci-msm 2>&1 | head -20
echo "== pci-msm / cnss dmesg"
dmesg 2>/dev/null | grep -i -E 'pci-msm|PCIe RC0|PCIe: RC0|cnss_pci|cnss2|wlan_en|link up|LTSSM' | head -80
echo "== lspci-ish"
ls /sys/bus/pci/devices 2>&1
for d in /sys/bus/pci/devices/*; do echo $d; cat $d/vendor $d/device 2>/dev/null; done
echo "== clk/regulator summary (pcie)"
ls /sys/kernel/debug/clk 2>&1 | head -3
echo "== wlan state"
getprop wifi.interface; getprop init.svc.wpa_supplicant; ip link 2>&1 | head -20
