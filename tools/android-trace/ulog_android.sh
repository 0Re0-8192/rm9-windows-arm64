for f in /sys/kernel/debug/charger_ulog /sys/kernel/debug/battery_charger_ulog /sys/kernel/debug/pmic_glink/charger_ulog; do [ -e $f ] && echo "have $f"; done
ls /sys/kernel/debug 2>/dev/null | grep -i -E "ulog|charger|glink|battery" | head
