# Adds an external-abort skipper to SpmiOwnershipProbeDxe: PmicDxe/SPMI.efi read the write-channel STATUS of EE0-owned-but-protected apids (APID646 = PM8550B sid7 0x4F00)
# and take a synchronous external abort.  The handler turns a faulting load from the SPMI chnls window into "returns 0" and resumes after it.
import re
p = '/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Drivers/SpmiOwnershipProbeDxe/SpmiOwnershipProbeDxe.c'
s = open(p).read()
if 'SpmiAbortSkip' in s:
    print('already patched'); raise SystemExit
s = s.replace('#include <Protocol/EFIScm.h>', '#include <Protocol/EFIScm.h>\n#include <Protocol/Cpu.h>\n#include <Protocol/DebugSupport.h>', 1)
handler = r'''
#define NX_SPMI_CHNLS_LO 0x0C500000ULL
#define NX_SPMI_CHNLS_HI 0x0C900000ULL
STATIC UINT32  mSkipCount;

// rm9: external abort on the SPMI write-channel window -> make the load return 0 and continue (SPMI.efi then reports "not done" and PmicDxe goes on)
STATIC VOID
EFIAPI
SpmiAbortSkip (IN EFI_EXCEPTION_TYPE Type, IN EFI_SYSTEM_CONTEXT Ctx)
{
  EFI_SYSTEM_CONTEXT_AARCH64 *C = Ctx.SystemContextAArch64;
  UINT32 Insn;

  if (((C->ESR >> 26) == 0x25) && (C->FAR >= NX_SPMI_CHNLS_LO) && (C->FAR < NX_SPMI_CHNLS_HI)) {
    Insn = *(UINT32 *)(UINTN)C->ELR;
    if ((Insn & 0x3B000000U) == 0x39000000U || (Insn & 0x3B200C00U) == 0x38200800U) {   // LDR/LDRB/LDRH (unsigned offset / register offset), loads only
      if ((Insn & 0x00400000U) != 0 && (Insn & 0x1F) != 31) {
        (&C->X0)[Insn & 0x1F] = 0;
        C->ELR += 4;
        mSkipCount++;
        if (mSkipCount <= 8) {
          DEBUG ((DEBUG_ERROR, "[SPMI-SKIP] #%u abort at FAR=0x%lx ELR=0x%lx insn=0x%08x -> Rt=0\n", mSkipCount, C->FAR, C->ELR - 4, Insn));
        }
        return;
      }
    }
  }
  // not ours: drop the handler so the faulting instruction re-faults into the default (printing) handler
  {
    EFI_CPU_ARCH_PROTOCOL *Cpu = NULL;
    if (!EFI_ERROR (gBS->LocateProtocol (&gEfiCpuArchProtocolGuid, NULL, (VOID **)&Cpu))) {
      Cpu->RegisterInterruptHandler (Cpu, EXCEPT_AARCH64_SYNCHRONOUS_EXCEPTIONS, NULL);
    }
  }
}
'''
s = s.replace('EFI_STATUS EFIAPI\nSpmiOwnershipProbeEntry', handler + '\nEFI_STATUS EFIAPI\nSpmiOwnershipProbeEntry', 1)
s = s.replace('  (VOID)ImageHandle;', '''  {
    EFI_CPU_ARCH_PROTOCOL *Cpu = NULL;
    EFI_STATUS St = gBS->LocateProtocol (&gEfiCpuArchProtocolGuid, NULL, (VOID **)&Cpu);
    if (!EFI_ERROR (St)) {
      St = Cpu->RegisterInterruptHandler (Cpu, EXCEPT_AARCH64_SYNCHRONOUS_EXCEPTIONS, SpmiAbortSkip);
    }
    DEBUG ((DEBUG_ERROR, "[SPMI-SKIP] abort skipper install: %r
", St));
  }
  (VOID)ImageHandle;''', 1)
open(p, 'w').write(s)
q = p.replace('.c', '.inf')
t = open(q).read()
if 'gEfiCpuArchProtocolGuid' not in t:
    t = t.replace('[Protocols]\n  gQcomScmProtocolGuid', '[Protocols]\n  gQcomScmProtocolGuid\n  gEfiCpuArchProtocolGuid', 1)
    open(q, 'w').write(t)
print('patched')
