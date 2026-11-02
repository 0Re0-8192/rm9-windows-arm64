# rm9-windows-arm64

Windows 11 ARM64 on the **RedMagic 9 Pro (ZTE/nubia NX769J, Snapdragon 8 Gen 3 / SM8650)**, started from the phone's own Android
with a custom UEFI. This repository is the working bench of that bring-up: the glue code that runs inside the UEFI, the
Windows kernel drivers written for it, the ACPI patches, the PC-side link, and the notes on what broke and why.

It is a research record, not a product. Expect device-specific offsets, one-off scripts, and a few things that only work on
the one phone they were written on.

## Status (2026-11)

| Area | State |
|---|---|
| Boot | Windows 11 ARM64 starts from the phone alone (`su -c boot_windows.sh` in Android; the Windows restart returns to Android). Two guests: build 28000 (26H1) and a clean 25H2 (26100) in a VHDX |
| Storage | UFS, all six LUNs, with write-protection of the Android LUNs (see [docs/gpt-incident.md](docs/gpt-incident.md)) |
| CPU | 8 cores; a software governor in `drivers/dbgcap` (Windows' own PPM does not load) |
| Display | Windows desktop and logon through the firmware's GOP framebuffer (CPU rendering, no GPU driver) |
| Input | Touch (HID), power and volume keys (read from the PMIC over SPMI) |
| Battery / thermal | Live battery state through ACPI and the ADSP; TSENS temperature; battery-temperature cut-off |
| USB | Device mode to a PC (custom link, `tools/pc-link`) and host mode |
| Wi-Fi | WCN7850 over PCIe: associates, DHCP, internet. Interrupt driven (see [docs/wifi-bringup.md](docs/wifi-bringup.md)) |
| Not done | GPU, audio, Bluetooth, camera, modem, sensors; real power-off (a Windows shutdown becomes a restart into Android) |
| Open problem | Unattended long runs are not yet trustworthy: see [docs/safety-lessons.md](docs/safety-lessons.md) |

## Read first: this can hurt a phone

Several of the tools here write to UFS partitions, talk to the bootloader, or run Windows on hardware that has no thermal or
power management of its own. Early in this project a Windows boot rewrote the GPT of every LUN and the phone had to be revived
through EDL; a hung Windows once cooked the battery. [docs/safety-lessons.md](docs/safety-lessons.md) lists every way it has
gone wrong. Read it before running anything, and do not run it on a phone you cannot afford to lose.

## What is here

```
src/muchain/        MuChain.c: the hardware bring-up that runs in the UEFI before Windows (PCIe0, RPMh, SPMI, UFS write
                    protect, watchdog keep-alive, battery hand-off, boot-time touch probe) and its build includes
tools/uefi-patch/   scripts that patch the UEFI image and the stock firmware (binary patchers, image builders)
tools/acpi/         DSDT/MCFG/IORT/MADT generators: battery, thermal, PCIe root complex, ITS, the interrupt device RM9I0001
tools/android-trace/ how the register sequences were learned: ftrace of MMIO on the running Android, DT surveys, dumps
tools/pc-link/      rm9link (UsbDk link to the phone), cycle runners, EDL/Sahara helpers, ESP file transfer
tools/gpt/          the GPT/unique-GUID analysis behind the incident
tools/windows-image/ reading and repairing the Windows images from outside (NTFS/VHDX/registry hives, BCD, update blocking)
guest/              what runs inside Windows: the staged run.cmd wrappers, keypoll/keyinject, touch, battery, Wi-Fi
host-scripts/       PC-side helpers for the second-PC setup and the 26100 guest
drivers/            dbgcap (watchdog guard, governor, Wi-Fi polling/kick), rm9io (MMIO from user mode), rm9irq (SPI -> ISR),
                    rm9hid (HID touch)
docs/               the write-ups
```

## What is not here

No firmware, partition dumps, Windows images, drivers from other vendors, signing keys, or device-unique data (serial numbers,
calibration, network credentials). Anything that needs those reads them from your own phone and your own Windows media. Paths
and identifiers that came from the author's machines are replaced by placeholders:

| Placeholder | Meaning |
|---|---|
| `<RM9_WORKDIR>` | the working directory the scripts were run from |
| `<PROJECTS>` | the parent directory of the other checkouts |
| `<PHONE_SERIAL>` | the adb/fastboot serial of the phone |
| `<EDL_SN>` | the serial shown in the EDL USB name (`QUSB_BULK_CID:0448_SN:...`) |
| `<LAB_SSID>`, `<PASSPHRASE>` | the test access point and its key |
| `<second-pc>`, `<user>`, `<email>` | machines and accounts |

The scripts will not run unmodified. They are here to show the method.

## Where to start

1. [docs/boot-flow.md](docs/boot-flow.md): how the phone gets from Android into Windows and back.
2. [docs/wifi-bringup.md](docs/wifi-bringup.md): the longest single piece of work, and the most reusable.
3. [docs/gpt-incident.md](docs/gpt-incident.md) and [docs/safety-lessons.md](docs/safety-lessons.md).

## Standing on

Project Mu and [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) for the UEFI base the launcher is built from, and the
Linux `qcom` drivers (pinctrl, clock, PCIe, SPMI), whose register layouts this work leans on throughout.
