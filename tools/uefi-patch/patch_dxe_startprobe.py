"""DxeCore: after every image's entry point returns, fire a MDP CTL_0 START (the display pipeline was left running by the bootloader; at SEC time a START
works, from MuChain on it kills the SoC) and log before/after.  The last '[PROBE] START after image ...' line without its 'ok' partner names the driver that broke the display
environment.  Idempotent.   usage (WSL): python3 patch_dxe_startprobe.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
p = Path("/root/Mu-Silicium/Mu_Basecore/MdeModulePkg/Core/Dxe/Image/Image.c")
o = p.with_suffix(".c.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    old = "    Image->Status  = Image->EntryPoint (ImageHandle, Image->Info.SystemTable);\n"
    assert old in t
    add = old + r'''    {  // RM9 START probe
      STATIC UINTN  Rm9Seq = 0;

      STATIC BOOLEAN  Rm9Mapped = FALSE;

      if (gCpu != NULL && !Rm9Mapped) {
        EFI_STATUS  Rm9S;

        Rm9S = CoreAddMemorySpace (EfiGcdMemoryTypeMemoryMappedIo, 0x0AE00000ULL, 0x200000, EFI_MEMORY_UC | EFI_MEMORY_XP);
        DEBUG ((DEBUG_ERROR, "[PROBE] map MDSS add: %r\n", Rm9S));
        Rm9S = CoreSetMemorySpaceAttributes (0x0AE00000ULL, 0x200000, EFI_MEMORY_UC | EFI_MEMORY_XP);
        DEBUG ((DEBUG_ERROR, "[PROBE] map MDSS attr: %r\n", Rm9S));
        Rm9Mapped = TRUE;
        *(volatile UINT32 *)(UINTN)0xD7FF0460ULL = 0x4D445353;
      }

      Rm9Seq++;
      if (Rm9Mapped) {
        DEBUG ((DEBUG_ERROR, "[PROBE] #%lu after image base=0x%lx ...\n", (UINT64)Rm9Seq, (UINT64)(UINTN)Image->Info.ImageBase));
        DEBUG ((DEBUG_ERROR, "[PROBE] #%lu hw=0x%08x flush=0x%08x gdsc=0x%08x ahb=0x%08x mdp=0x%08x\n", (UINT64)Rm9Seq, *(volatile UINT32 *)(UINTN)0x0AE00000ULL, *(volatile UINT32 *)(UINTN)0x0AE16018ULL, *(volatile UINT32 *)(UINTN)0x0AF09000ULL, *(volatile UINT32 *)(UINTN)0x0AF080A4ULL, *(volatile UINT32 *)(UINTN)0x0AF08038ULL));
      }
    }
'''
    t = t.replace(old, add, 1)
p.write_text(t, encoding="utf-8")
print("DxeCore START probe:", mode)


