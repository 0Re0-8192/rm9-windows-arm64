"""One-off patch for MuChain.c: also hook whole-disk BlockIo reads, log read status,
fix the Windows partition last-block constant (0x1FE4CB6)."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")

t = t.replace("  UINT64                 LastBlock;\n  UINT64                 Count;",
              "  UINT64                 LastBlock;\n  BOOLEAN                Logical;\n  UINT64                 Count;")
t = t.replace("    if (!B->Media->LogicalPartition) {\n      continue;\n    }\n    mHooks[mHookCount].Block     = B;",
              "    if (!B->Media->MediaPresent) {\n      continue;\n    }\n    mHooks[mHookCount].Logical   = B->Media->LogicalPartition;\n    mHooks[mHookCount].Block     = B;")

old = """      H->Blocks += BufferSize / This->Media->BlockSize;
      if (H->Count <= LOG_FIRST_N || (H->Count % LOG_EVERY_N) == 0) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] rd part(last=0x%lx) #%lu lba=0x%lx bytes=%lu\\n",
                H->LastBlock, H->Count, (UINT64)Lba, (UINT64)BufferSize));
      }
      return H->OrigRead (This, MediaId, Lba, BufferSize, Buffer);
"""
new = """      EFI_STATUS Rs;
      H->Blocks += BufferSize / This->Media->BlockSize;
      Rs = H->OrigRead (This, MediaId, Lba, BufferSize, Buffer);
      if (H->Count <= LOG_FIRST_N || (H->Count % LOG_EVERY_N) == 0 || EFI_ERROR (Rs) ||
          (!H->Logical && Lba >= 28078888ULL && Lba <= 61521886ULL)) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] %a(last=0x%lx) #%lu lba=0x%lx bytes=%lu -> %r\\n",
                H->Logical ? "PARTREAD" : "DISKREAD", H->LastBlock, H->Count, (UINT64)Lba, (UINT64)BufferSize, Rs));
      }
      return Rs;
"""
assert old in t, "read-hook pattern not found"
t = t.replace(old, new)
t = t.replace("0x1FEA3B6ULL", "0x1FE4CB6ULL")
t = t.replace("#define LOG_FIRST_N     48", "#define LOG_FIRST_N     24")
p.write_text(t, encoding="utf-8")
print("patched")
