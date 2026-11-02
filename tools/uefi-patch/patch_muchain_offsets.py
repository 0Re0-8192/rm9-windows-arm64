"""Move MuChain's breadcrumb markers to 0xD7FF0400+ (the DSDT now uses 0xD7FF0000..0x1FF)
and clear 0x500 bytes at start."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")
rep = {
    "0xD7FF00F0ULL": "0xD7FF0400ULL",
    "0xD7FF00F4ULL": "0xD7FF0404ULL",
    "0xD7FF00F8ULL": "0xD7FF0408ULL",
    "0xD7FF0100ULL": "0xD7FF0410ULL",
    "0xD7FF0110ULL": "0xD7FF0420ULL",
    "0xD7FF0114ULL": "0xD7FF0424ULL",
}
for a, b in rep.items():
    t = t.replace(a, b)
t = t.replace("ZeroMem ((VOID *)(UINTN)0xD7FF0000ULL, 0x100);", "ZeroMem ((VOID *)(UINTN)0xD7FF0000ULL, 0x500);")
p.write_text(t, encoding="utf-8")
print("ok", t.count("0xD7FF04"))
