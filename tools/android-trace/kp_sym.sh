grep -i -E " (pmic_glink_write|pmic_glink_send|battery_chg_write|battery_chg_callback|battery_chg_read|battery_psy_get_prop|battery_chg_get_prop|qti_battery_charger)" /proc/kallsyms | head -20
echo ---; grep -c . /proc/kallsyms
echo ---; ls /sys/kernel/tracing 2>/dev/null | head -3; ls /sys/kernel/debug/tracing 2>/dev/null | head -3
