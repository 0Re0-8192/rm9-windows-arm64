#!/system/bin/sh
# read-only: does anything on this Android depend on partition unique GUIDs (PARTUUID)?
echo "--- cmdline PARTUUID/root"
cat /proc/cmdline | tr ' ' '\n' | grep -i -E 'partuuid|root=|boot_devices|slot'
echo "--- fstab PARTUUID/UUID uses"
grep -l -i -E 'partuuid|uuid=' /vendor/etc/fstab.* /system/etc/fstab.* /fstab.* /first_stage_ramdisk/fstab.* 2>/dev/null
grep -h -i -E 'partuuid|uuid=' /vendor/etc/fstab.* /system/etc/fstab.* /fstab.* /first_stage_ramdisk/fstab.* 2>/dev/null | head
echo "--- by-partuuid exists? (symlink dir)"
ls /dev/block/by-partuuid 2>&1 | head -3
ls /dev/block/platform/*/by-name 2>/dev/null | head -3
echo "--- init rc / scripts mentioning partuuid"
grep -r -l -i 'partuuid' /vendor/etc/init /system/etc/init /init*.rc /vendor/bin 2>/dev/null | head
echo "--- sample unique GUID of userdata (from sysfs, kernel-parsed GPT)"
cat /sys/class/block/sda*/uevent 2>/dev/null | grep -E 'PARTNAME|PARTUUID' | head -6
