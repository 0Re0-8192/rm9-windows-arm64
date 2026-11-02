dmesg | grep -i -E "cnss|wlan|pcie.*0:|WCN|qmp|aoss|pmu|bdf|firmware ready|PCIe: Link|link up|Link is up|BT_EN|WLAN_EN|SW_CTRL" | head -${1:-80} | cut -c1-210
