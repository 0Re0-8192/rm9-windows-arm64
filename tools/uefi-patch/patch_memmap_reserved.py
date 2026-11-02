#!/usr/bin/env python3
"""Add DTS `no-map` reserved-memory regions that the nx769j Mu memory map is
missing (RamManagerDxe maps every gap of the DDR ranges as free RAM, so the OS
loader / Windows would allocate protected memory and take an external abort).

Idempotent.  Run in WSL.  Backs up MemoryMapLib.c to .bak_nomap once.
"""
import re
import shutil
from pathlib import Path

p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Library/MemoryMapLib/MemoryMapLib.c")
bak = p.with_suffix(".c.bak_nomap")
if not bak.exists():
    shutil.copy2(p, bak)
s = p.read_text(encoding="utf-8")

R = 'AddMem, MEM_RES, UNCACHEABLE, Reserv, UNCACHED_UNBUFFERED_XN}'


def ent(name, a, l):
    return '  {"%-18s 0x%08x, 0x%08x, %s,\n' % (name + '",', a, l, R)


def insert_after(s, anchor_name, text, marker):
    if marker in s:
        return s
    m = re.search(r'\n  \{"%s",[^\n]*\n' % re.escape(anchor_name), s)
    assert m, anchor_name
    return s[:m.end()] + text + s[m.end():]


s = insert_after(s, "AOP", ent("aop_tme_uefi_hi", 0x81CA0000, 0x44000), "aop_tme_uefi_hi")
s = insert_after(s, "UEFI_Log", ent("chipinfo_region", 0x81CF4000, 0x1000), "chipinfo_region")
s = insert_after(s, "SMEM", ent("adsp_mhi_region", 0x81F00000, 0x20000), "adsp_mhi_region")
s = insert_after(
    s, "PvmFw",
    ent("global_sync_region", 0x82600000, 0x100000)
    + ent("tz_stat_region", 0x82700000, 0x100000)
    + ent("qlink_logging", 0x84800000, 0x200000)
    + ent("mpss_dsm_region", 0x86B00000, 0x4900000)
    + ent("mpss_dsm_region_2", 0x8B400000, 0x800000),
    "global_sync_region")
s = insert_after(s, "RamConsole", ent("tz_merged_region", 0xD8000000, 0x800000), "tz_merged_region")

# DXE_Heap1 overlapped hwfence-shmem (no-map 0xe6440000-0xe671d000): split.
old = '{"DXE_Heap1",          0xE6440000, 0x0CDC0000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv,   WRITE_BACK_XN},'
new = ('{"hwfence_shmem",      0xE6440000, 0x002DD000, ' + R + ',\n'
       '  {"DXE_Heap1",          0xE671D000, 0x0CAE3000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv,   WRITE_BACK_XN},')
if "hwfence_shmem" not in s:
    assert old in s, "DXE_Heap1 line not found"
    s = s.replace(old, new)

last_old = '  {"DXE_Heap1",'
# llcc_lpi_region goes after DXE_Heap1 (DDR end 0x100000000 > 0xff800000)
if "llcc_lpi_region" not in s:
    m = re.search(r'\n  \{"DXE_Heap1",[^\n]*\n', s)
    s = s[:m.end()] + ent("llcc_lpi_region", 0xFF800000, 0x600000) + s[m.end():]

p.write_text(s, encoding="utf-8")
print("patched", p)
