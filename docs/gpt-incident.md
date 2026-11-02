# The GPT incident: how a Windows boot took the phone to EDL

2026-10-13. This is the one that nearly ended the project, and it can happen to anyone who boots Windows on a UFS phone that has
several LUNs with similar partition tables.

## What happened

After the first successful Windows boot (UEFI to `bootmgfw` to `winload` to `ExitBootServices`), the phone did not come back. It was
in EDL. Windows' `storufs` driver had rewritten the GPT header on all six UFS LUNs. Android was intact (the data was untouched),
but the boot chain could no longer find its partitions.

## Why

The phone's LUNs share **partition unique GUIDs** across LUNs: the same GUIDs appear in the partition tables of more than one
LUN. Windows took that as a signature collision and, when it brought the disks online, rewrote the GPT of the colliding disks.
This was reproduced off-device with WinPE under QEMU using copies of the LUNs' partition tables (`tools/gpt/gpt_collisions.py`,
`gpt_unique_guids.py`, `lun_dups.py`, `lun_guids.py`).

## Recovery

EDL can be entered with the volume buttons held while connecting USB, with the battery connected. Through it, the LBA 1 GPT
header of each affected LUN was reconstructed. Android started normally. (Keep your own full backups of every
LUN's first and last sectors before any experiment; they are tiny.)

## Prevention, in the order it was applied

1. **Make the GUIDs unique.** The partition unique GUIDs of LUN0 and LUN5 were rewritten so that no two LUNs share one. Applied
   on the phone and verified.
2. **Write-protect the LUNs Windows should not touch.** UFS has a power-on write protect: a flag set from the host that holds
   until the next reset. MuChain sets it just before `ExitBootServices` to cover LUN1 to LUN4, so even if Windows decides to
   rewrite a GPT, the device refuses. Verified on the phone.
3. **Keep the others offline.** `SanPolicy=4` (all disks offline) in the Windows image, so the disks Windows sees are not
   brought online on their own.
4. **Observation.** UFS host-controller registers are logged from AML (`UFSS`) so that a failing boot can be read afterwards, and
   the Windows hive of the phone can be read from outside to see which devices were enumerated (`tools/windows-image/hive_enum.py`).

## What to check on a different phone

* Whether the same partition-level GUIDs appear on more than one LUN (`tools/gpt`).
* Whether your boot chain can set write protect on the LUNs before the OS starts.
* That you can reach EDL (or have another way to rewrite a GPT) before the first Windows boot, not after.
