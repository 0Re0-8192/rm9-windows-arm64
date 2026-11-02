#!/system/bin/sh
lsmod | grep -i -E 'cld|wlan|kiwi|cnss|pci_msm|qca'
echo "== module files"
find /vendor/lib/modules /vendor_dlkm /system/lib/modules -iname '*cld*' -o -iname '*wlan*' -o -iname '*kiwi*' 2>/dev/null | head
echo "== dmesg: msm_pcie_enable_link times"
dmesg | grep -E 'msm_pcie_enable_link|PHY is ready|msm_pcie_disable|insmod|Direct firmware load for kiwi/amss20' | cut -c1-120 | tail -20
echo "== wifi props"
getprop vendor.wlan.driver.status; getprop wlan.driver.status
