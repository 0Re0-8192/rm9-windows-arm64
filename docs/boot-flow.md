# Boot flow

How the phone gets into Windows and back, as of 2026-11. Everything here is specific to the NX769J.

## Slots

The phone has A/B slots. Slot **b** is the everyday Android. Slot **a** carries the launcher: a Mu-based UEFI (`boot_a`) that
runs once, starts Windows, and is consumed. `su -c boot_windows.sh` (in `tools/android-trace`) arms it and reboots; the
phone returns to Android on its own after the Windows session ends (about 4.5 to 5 minutes after a Windows restart).

Two cautions learned the hard way:

* `vendor_boot_a` is not a normal partition: it is an ext4 image used as a modified component (mounted through the ramdisk
  fstab of slot b). Overwriting it sends Android into a panic loop. Read the ramdisk fstab before overwriting anything in
  slot a.
* Setting the active slot lowers slot b's "successful" mark; Android raises it again once it boots.

## UEFI stage: MuChain

`src/muchain/MuChain.c` runs in the UEFI just before the Windows boot manager. It does what Windows cannot yet do for itself:

* brings up PCIe0 and the WLAN chip (rails through RPMh, a sleep clock through the PMIC, the PHY sequence, link training), and
  leaves the link up for Windows (see [wifi-bringup.md](wifi-bringup.md));
* sets the UFS power-on write protect on LUN1 to LUN4 just before ExitBootServices;
* asks the ADSP for battery state over pmic_glink and leaves it in a fixed RAM slot that an ACPI battery device reads;
* probes the touch controller before the ADSP starts;
* keeps the Gunyah watchdog alive across ExitBootServices (see [safety-lessons.md](safety-lessons.md)).

The ACPI tables are patched by `tools/acpi`: battery and AC, thermal, a PCI root complex (`PCI0`), MCFG, IORT/ITS, and the
interrupt device `RM9I0001`.

## Windows stage: a staged `run.cmd`

A fixed bootstrap (`C:\rm9\diag.cmd`, started by a service on every boot) mounts the EFI system partition as `S:` and runs
`S:\rm9\run.cmd`. Because the ESP is FAT, `run.cmd` can be edited from Android in seconds, which makes it the experiment loop.
Every `run.cmd` ends by cancelling the bootstrap's safety restart and issuing its own `shutdown /r`.

The clean 26100 guest uses a staged wrapper (`guest/esp_run_26100_acct.cmd`): account and computer name, then the test-signed
drivers, then the USB function configuration, then the Wi-Fi driver, then the production `run.cmd`. Each stage leaves a flag
file and restarts, so a first run needs several boots.

The production `run.cmd` (`guest/esp_run_prod_wifi.cmd`) starts the PC link, the battery updater, the Wi-Fi fix-ups, and
`guard.cmd`, which starts the `dbgcap` safety driver, and schedules a 40-minute restart as a last resort.

## Talking to the phone

`tools/pc-link/rm9link.py` speaks a small protocol over a USB function that Windows exposes (VID 1209), through UsbDk on the
PC (ping, exec, put, get, reboot). `run_cycle_bg.ps1` and `two_cycle.ps1` run a test cycle: put a `run.cmd`, boot Windows,
wait for it to come back to Android, and collect the logs by reading the Windows volume from outside
(`tools/windows-image/ntfs_*.py`, `vhdx_ntfs_remote.py`). Reading the volume right after a crash can miss the newest writes,
because the NTFS journal has not been replayed.
