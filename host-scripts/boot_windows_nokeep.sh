#!/system/bin/sh
# boot_windows.sh - run as root on the phone's Android: restart into Windows without a PC (slot-a launcher), one shot.
#   su -c /data/local/tmp/rm9win/boot_windows.sh          start Windows
#   su -c "/data/local/tmp/rm9win/boot_windows.sh dry"    do everything except switching the slot and rebooting
# How it works (NEXT.md 0bx): boot_a = boot image header v2 (Mu UEFI as the kernel + the platform dtb; ABL needs no vendor_boot_a, which is an ext4 image here), vbmeta_a = flags 2 (verification disabled).
# The logdump partition gets muchain_esp_once.img = the production MuChain build + \ONCEMODE.TXT + \ONCE.TXT.  MuChain only starts Windows when \ONCE.TXT can be
# consumed; the boots of slot a that follow (ABL retries it while the retry count lasts) reset at once, so ABL finally falls back to slot b = Android.
D=/data/local/tmp/rm9win
IMG=/data/local/tmp/muchain_esp_once_nokeep.img
ESPD=$D/mnt_esp
BC=android.hardware.boot.IBootControl/default
fail() { echo "boot_windows: $1" >&2; umount $ESPD 2>/dev/null; exit 1; }
[ "$(getprop ro.boot.slot_suffix)" = "_b" ] || fail "Android is not running from slot b"
[ -f $IMG ] || fail "$IMG missing"
[ "$(stat -c %s $IMG)" = "67108864" ] || fail "$IMG has the wrong size"
# boot_a must be the v2 launcher image (header version 2 at offset 40) and vbmeta_a the verification-disabled one (flags=2 at offset 123)
hv=$(dd if=/dev/block/by-name/boot_a bs=1 skip=40 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
[ "$hv" = "2" ] || fail "boot_a is not the v2 launcher image (header version $hv)"
vf=$(dd if=/dev/block/by-name/vbmeta_a bs=1 skip=123 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
[ "$vf" = "2" ] || fail "vbmeta_a is not the verification-disabled image (flags $vf)"
# 1. logdump <- MuChain + once flags (verified)
dd if=$IMG of=/dev/block/by-name/logdump bs=1048576 2>/dev/null || fail "writing logdump failed"
sync
want=$(sha256sum $IMG | cut -d' ' -f1)
got=$(dd if=/dev/block/by-name/logdump bs=1048576 count=64 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$want" = "$got" ] || fail "logdump verify failed"
# 2. clock for Windows (no RTC): ESP rm9/time.txt
mkdir -p $ESPD
mount -t vfat -o rw,nosuid,nodev,noexec /dev/block/by-name/esp $ESPD || fail "cannot mount esp"
[ -d $ESPD/rm9 ] || fail "esp has no rm9 directory"
date '+%Y-%m-%d %H:%M:%S' > $ESPD/rm9/time.txt
cp /data/local/tmp/BCD.try2 $ESPD/EFI/Microsoft/Boot/BCD || fail "BCD copy failed"
sync
umount $ESPD
echo "logdump armed, clock written: $(date '+%F %T')"
[ "$1" = "dry" ] && { echo "dry run: slot not switched"; exit 0; }
# 3. slot a active (AIDL boot control: 9 = setActiveBootSlot), then check
service call $BC 9 i32 0 >/dev/null
case "$(service call $BC 1)" in *"00000000 00000000"*) ;; *) fail "active slot is not a after setActiveBootSlot";; esac
echo "active slot -> a; rebooting into Mu/Windows"
sync
reboot
