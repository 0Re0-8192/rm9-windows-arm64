# Wi-Fi bring-up: WCN7850 on a phone SoC under Windows

The WLAN chip of this phone (Qualcomm WCN7850 / FastConnect 7800, PCI `17cb:1107`) hangs off PCIe0. Android brings it up through
the kernel and the CNSS driver. Windows has a driver for the chip (written for the X Elite laptops) but nothing that brings up the
SoC side. This is the path from "no link" to "associates, gets an address, pings", in the order the problems showed up. Each
step was found by comparing against what Android does, or by cutting the failing step down until one cause remained.

Dates are 2026-10; the register values are for this SM8650 board.

## 1. Learn what Android does

Android's kernel has `CONFIG_TRACE_MMIO_ACCESS`. With `events/rwmmio` enabled in ftrace, unloading and re-loading the WLAN
module makes CNSS power the chip off and on and run the whole link-enable sequence, which lands in the trace
(`tools/android-trace/android_trace_pcie3.sh`, filtered by `mmio_window.py`, `mmio_pre.py`, `mmio_filter.py`).
That gave the order: GPIO (WLAN_EN, PERST#, CLKREQ#, WAKE), RPMh rails, PARF registers, the 114-entry PHY table, PERST# release
about 12 ms after the PHY is ready, then the DesignWare DBI configuration (one lane, equalisation), and finally the LTSSM enable.
The link is up about 16 ms later. The PHY table is in the device tree (`qcom,phy-sequence`); `tools/uefi-patch/gen_pcie_physeq.py`
turns it into `src/muchain/pcie_physeq.h`.

Two things to avoid while doing this on a live phone. A debugfs dump of the PCIe register space (`pci-msm`) can hang the SoC
into the Sahara memory-debug (dump) mode, and reading the `phy` base there is a kernel panic. The way out of dump mode is
`tools/pc-link/sahara_reset.ps1`.

## 2. The link that would not train

Replaying the sequence in UEFI got the PHY ready and the root complex readable, but the LTSSM kept cycling between
`DETECT_QUIET` and `DETECT_ACT`: no receiver detected. The rails, the clocks and the sleep clock (a PMK8550 GPIO configured as
an alternate-function clock output) were all as Android had them.

The missing piece was two TLMM registers. Before it enables WLAN_EN, Android writes `0x7c2` to the `INTR_CFG` register of
GPIO18 and GPIO19 (the `mpm_wake_set_gpios` of the CNSS device tree node), and the same value for the WAKE line GPIO96. That
connects the chip's SW_CTRL to the MPM/PDC and, through AOP, makes the chip's supply rails come up to their operating voltage.
Without it the chip is half-powered and invisible. With it: Gen1 x2 link, endpoint ID `0x110717CB`.

The reason it took about a week: the comparison had been limited to the GPIOs everyone knows about (16, 94, 95, 96). The power-on
window's TLMM writes were never diffed across the whole TLMM. **Diff every address in the window, not the ones you expect.**

## 3. Windows sees a PCI device

Windows needs ECAM to enumerate PCI. The DesignWare iATU can be put in CFG shift mode so that the bus-1 window at
`0x60100000` acts as an ECAM region (device 0 answers, everything else returns UR). The ACPI side is a `PCI0` host bridge
(`PNP0A08`, root bus 1) plus an MCFG table. Two details cost time: the MCFG base is the *bus-0* position (`0x60000000`) with the
start bus set to 1, and a DSDT that contains `PCI0` must only be booted together with a firmware that has already trained the link,
or Windows reads an uninitialised ECAM and stops.

Windows then lists `PCI\VEN_17CB&DEV_1107`.

## 4. MSI: where it stopped for over a week

The driver (`qcwlanhmt8380`) binds, then Windows' HAL programs MSI through the GIC ITS and the machine dies with
`CLOCK_WATCHDOG_TIMEOUT`: the ITS stalls (`GITS_CREADR` stops advancing) and a CPU waits on it forever. The phone runs Windows as a
guest of the Gunyah hypervisor, which virtualises the GIC and the ITS; ITS commands that change the tables (MAPD, MAPC, MAPTI,
DISCARD) sent from Windows stop the machine. Do not send them.

## 5. Polling, to see the chip work at all

With no interrupts reaching the driver, the driver's own interrupt handlers were called from a kernel driver instead. A work item at
PASSIVE_LEVEL (a DPC at DISPATCH_LEVEL deadlocks the driver's waits) calls the MHI controller's and the copy engines' handlers
every few milliseconds. The driver needed two small patches to export those handlers; the work item lives in `drivers/dbgcap`.
Result: SBL, BHIe, AMSS, QMI/WLFW, `FW_INIT_DONE`, HTC and WMI came up, and a scan listed twenty networks in range.

Associating then failed in a particular way: the connection came up, and about seven seconds later Windows stopped. The packet
trace (ETW, `tracerpt` to CSV) showed no EAPOL from the access point and then a Deauth. The poller covered MHI and the copy
engines, but not the **ext groups**, which carry the data path: REO (receive) and TX completion. So the 4-way handshake never
arrived, the AP gave up, and the teardown was what stopped Windows. Calling the ext-group handlers too (`DpPoll` in
`drivers/dbgcap`) fixed it: association, DHCP, `ping 8.8.8.8`. Running the poll at PASSIVE_LEVEL also removed the stop on
disconnect.

## 6. The restart that hangs

Windows registers the root port's own MSI with the ITS (DeviceID `0x1301`). When the node is stopped, deleted, or the machine
restarts, it sends `MAPD` with V=0 for that device, and the hypervisor answers "unimplemented": the root port is a virtual device
to it, and only the endpoint (`0x1401`) is physical. The ITS stalls and Gunyah goes with it. That was behind two long-standing
symptoms: a boot with stale PCI nodes from the previous run hanging after about 170 seconds, and any attempt to remove the nodes
at shutdown freezing the machine (which is why the early setup used a sacrificial "clean-up" boot before every real one).

The way around it is to keep the root port out of MSI: set its `Interrupt Pin` to 1 (DBI offset `0x3C`, after unlocking the read-only
field with bit 0 of `MISC_CONTROL_1` at `0x8BC`), so Windows uses INTx for it through `_PRT`, and never registers the root port's
MSI. MuChain does this before Windows starts; `guest/rpfix.ps1` can do it live. After that the clean-up boot was unnecessary.

## 7. Interrupts, properly

The chip's MSI target can be pointed at something other than the ITS. The GIC exposes message-based-interrupt (MBI) frames; with the
chip's MSI address set to the MBI frame at `0x17110040` and the data to `800 + vector`, the interrupt arrives in the VM as a plain
**SPI** (800 to 811). Windows still has to be told about those SPIs. A device enumerated from the root has its resources
translated wrongly on ARM64 (an `IRQConfig` fails with `STATUS_NOT_FOUND`), so the DSDT gets a real ACPI device,
`RM9I0001`, whose `_CRS` declares the edge interrupts 800 to 811 (`tools/acpi/add_irq.py`). A tiny driver (`drivers/rm9irq`)
binds to it and connects all twelve with `IoConnectInterruptEx`. Its ISR signals a named event; a kernel thread in
`dbgcap` waits on it and runs the same poll routine the polling mode used, instead of timing it. The periodic poll stays as a
slow safety net.

Measured: no packet loss from the start of boot, about 45 Mbit/s with 5 ms / 30 ms kick settings (a tuned run reached 80 to
97 Mbit/s but wakes the CPU far more often), around 66 wakeups a second at idle. This is integrated into the production
`run.cmd` (`guest/esp_run_prod_wifi.cmd`, `guest/rpfix.ps1` in resident mode).

## Why the ITS path itself still does not work

A device-side LPI never reaches the guest here. It was tried through the SMMU with the device ID candidates and with
Android-style IOVAs, with no success, and the table state, WFI and IAR behaviour were each ruled out. This repository gets
around it rather than explaining it, and the Gunyah sources are the place to keep looking.

## Lessons that generalise

* Compare against the working system at every address, not at the ones you suspect.
* Record the working system's own sequence (MMIO tracing) instead of reconstructing it from source.
* A hypervisor's "unimplemented" for a virtual device can show up as a hang much later, at teardown.
* When a stage depends on interrupts, polling is a good first step because it separates "the chip works" from "the interrupt
  path works", but make sure the polled set is the whole set (the data path ext groups were the bug).
