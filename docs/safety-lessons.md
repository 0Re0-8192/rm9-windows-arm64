# Safety lessons
日本語版: [ja/safety-lessons.md](ja/safety-lessons.md)

Everything below actually happened on this project. The common thread: Windows on this phone has no power or thermal management
of its own, and it can stop in ways that neither the phone nor the PC notices, so the safeguards have to be built before the
unattended runs, not after.

## 1. A hung Windows cooked the battery (2026-10-27)

Windows froze (a stopped screen, not a BSOD) and was left for about ten hours. The case was very hot and both cells of the
battery swelled. The cause was the design: MuChain stops the Gunyah watchdog at `ExitBootServices` so Windows has time to start,
Windows had no thermal control (the processor power manager fails to load), and the "restart after 40 minutes" safeguard in
`run.cmd` needs a live Windows to run.

What replaced it (`drivers/dbgcap`):

* **Watchdog keep-alive.** MuChain passes the watchdog on to Windows still running. Once `dbgcap` loads, it re-arms the watchdog
  and pings it once a second, but only while the 500 ms timer DPC runs on every CPU and the temperature is acceptable. If Windows
  stops, the pings stop and the phone resets about 30 seconds later. The ping has to be an `smc #0` from the kernel (an HVC does
  not reach the watchdog), which is a small `armasm64` stub (`drivers/dbgcap/smc.asm`).
* **Battery temperature cut-off.** The battery temperature (from the same RAM block the ACPI battery uses) is read every second.
  Above 40 °C the performance budget is reduced; at 48 °C for ten seconds the pings stop and the phone restarts into Android.
* **A software CPU governor.** Because there is no PPM, `dbgcap` reads the load every 100 ms and sets the EPSS performance states
  itself, with a thermal budget on top.

The guard works only after `dbgcap` has been started by `run.cmd`. The early boot and the "clean-up" boots are unprotected.
Do not run unattended before checking that a hang really ends in a reset.

## 2. A Windows Update made it unbootable (2026-10-19)

Over a USB network connection, Windows Update replaced the OS (28000.1 to a newer build): kernel, loader, code-integrity policy and
about 3700 files. After the next restart it no longer booted. The phone's loader accepts the old files and refuses the new ones
(the new `winload` requires a code-integrity policy that this environment does not load; the system hive also needed rebuilding).

Recovery: read the Windows partition into a PC, roll the files back from the copies in WinSxS, and write back only the changed
chunks. Then stop the update from coming back: move `WinSxS\pending.xml` aside, disable the update services and
`TrustedInstaller`, and set the update policies (`tools/windows-image/neutralize_update.py`, `disable_wu_offline.py`).

Take-aways: save a base image before the first run and take a new one whenever a Windows run changes it. Writing a diff against a
stale base leaves NTFS inconsistent. Anything that gives Windows internet access can trigger an update on its own.

## 3. Others

* **Rewriting every LUN's GPT:** see [gpt-incident.md](gpt-incident.md).
* **Register dumps through debugfs hang the SoC** into the Sahara memory-debug mode (and reading the PCIe `phy` base panics the
  kernel). The way back is a Sahara reset from the PC (`tools/pc-link/sahara_reset.ps1`). Dump one block at a time.
* **Installing a driver for a device that is already present binds it at once.** `pnputil /add-driver ... /install` for the
  WLAN driver froze Windows because the driver started on a chip whose interrupts could not arrive. Disable the endpoint first and
  install with `Start=4`; if the machine dies before userland, set the service's `Start` back to 4 in the image's SYSTEM hive
  from outside (`host-scripts/offline_fix.ps1`).
* **`New-Item -Force` on a registry key deletes the key's values.** It wiped the WLAN service's `ImagePath` and the device showed
  a registry problem.
* **PowerShell hex literals above `0x7FFFFFFF` are negative `Int32`s.** An IOCTL code like `0x8F002820` failed the conversion to
  `uint`, the exception was swallowed, and six test cycles were spent looking for a driver bug. Build such values with
  `[Convert]::ToUInt32('8F002820', 16)` and log exceptions.
* **Windows' own restart returns to Android.** There is no real power-off: a Windows shutdown ends in the charging screen
  or needs a long press; the launcher treats every end as a restart into Android.
* **Do not send ITS-changing commands from Windows** (see [wifi-bringup.md](wifi-bringup.md)) and do not read unknown physical
  addresses: both stop the machine. Do not make a boot-start driver write to disk (it hung early boot), and write ETW traces to
  circular files: a plain trace file on the ESP was corrupted when the machine stopped.
* **A fastboot that does not enumerate was a bad USB port**, not the cable. Changing the port fixed it.
* **`esp_put.ps1` can silently write an empty file** if given a path with doubled backslashes. Check the size after every write to
  the ESP.

## 4. Still open (2026-11-02)

The watchdog-bite test on the 26100 guest with Wi-Fi up (stop the pings on purpose and wait for the reset) did not return the phone
to Android: it reappeared as an EDL device (`19D2:0112`, USB name `QUSB_BULK_CID:0448_SN:...`, which shows as an error without
a Qualcomm serial driver, and is easy to mistake for another device) and then stopped answering on USB. An earlier run of the same
kind of test recovered; it is believed to have been without the WLAN link, but that is a guess. The cause is not known. Until it
is, treat "the guard resets a hung Windows" as proven only for the earlier configuration, and do not run unattended with Wi-Fi up.
