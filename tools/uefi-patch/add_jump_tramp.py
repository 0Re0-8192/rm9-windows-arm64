NL = chr(10)
p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
assert 'JumpToKernel' not in s
tramp = r'''// Last step of the Linux handoff, all in registers (no stack): turn the MMU and D-cache off, clean + invalidate the whole D-cache by set/way (stale dirty lines of Mu's stack would otherwise be written back over
// Linux's memory later), invalidate the I-cache, branch to the entry with x0 = FDT.  Calling ArmDisableDataCache () from C and then returning into a frame whose stack lines were still dirty in the cache hung here.
__attribute__ ((naked, noreturn)) STATIC VOID
JumpToKernel (IN UINT64 Fdt, IN UINT64 Entry)
{
  __asm__ volatile (
    "mov x19, x0\n"
    "mov x20, x1\n"
    "mov x4, #5\n"                    // SCTLR.M | SCTLR.C
    "mrs x2, CurrentEL\n"
    "cmp x2, #8\n"
    "b.eq 1f\n"
    "mrs x3, sctlr_el1\n"
    "bic x3, x3, x4\n"
    "msr sctlr_el1, x3\n"
    "b 2f\n"
    "1:\n"
    "mrs x3, sctlr_el2\n"
    "bic x3, x3, x4\n"
    "msr sctlr_el2, x3\n"
    "2:\n"
    "isb\n"
    "ic iallu\n"
    "dsb sy\n"
    "isb\n"
    "mrs x0, clidr_el1\n"
    "ubfx x1, x0, #24, #3\n"          // LoC
    "cbz x1, 9f\n"
    "mov x2, #0\n"                    // x2 = level << 1
    "3:\n"
    "add x3, x2, x2, lsr #1\n"        // level * 3
    "lsr x3, x0, x3\n"
    "and x3, x3, #7\n"
    "cmp x3, #2\n"
    "b.lt 8f\n"                       // no data / unified cache at this level
    "msr csselr_el1, x2\n"
    "isb\n"
    "mrs x4, ccsidr_el1\n"
    "and x5, x4, #7\n"
    "add x5, x5, #4\n"                // line shift
    "ubfx x6, x4, #3, #10\n"          // max way
    "ubfx x7, x4, #13, #15\n"         // max set
    "clz w8, w6\n"                    // way shift
    "4:\n"
    "mov x9, x7\n"
    "5:\n"
    "lsl x10, x6, x8\n"
    "lsl x11, x9, x5\n"
    "orr x10, x10, x11\n"
    "orr x10, x10, x2\n"
    "dc cisw, x10\n"
    "subs x9, x9, #1\n"
    "b.ge 5b\n"
    "subs x6, x6, #1\n"
    "b.ge 4b\n"
    "8:\n"
    "add x2, x2, #2\n"
    "lsr x3, x2, #1\n"
    "cmp x3, x1\n"
    "b.lt 3b\n"
    "9:\n"
    "dsb sy\n"
    "isb\n"
    "ic iallu\n"
    "dsb sy\n"
    "isb\n"
    "mov x0, x19\n"
    "mov x1, #0\n"
    "mov x2, #0\n"
    "mov x3, #0\n"
    "br x20\n"
  );
}

'''
key = '// Clean + invalidate the whole data cache by set/way'
assert key in s
s = s.replace(key, tramp + key, 1)
a = s.index('  ArmDisableDataCache ();' + NL + '  FlushDcacheAll ();')
b = s.index('  CpuDeadLoop ();', a)
new = ('  Crumb (3, 0x0000FF00);                       // about to run the trampoline (MMU / D-cache off, set/way flush, branch)' + NL +
       '  JumpToKernel ((UINT64)(UINTN)Fdt, ((UINT64)0xA8000000ULL));' + NL)
s = s[:a] + new + s[b:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
