"""MuChain.c: in every Tr* service wrapper, store (service code, running count) at fixed addresses
 0xD7FF0110 = last service code (high 8 bits) | low 24 bits of last argument
 0xD7FF0114 = running count of all traced service calls
and stop logging HandleProtocol/OpenProtocol/BlockIo lines once ExitBootServices has begun."""
import re
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")

if "MARKSVC" not in t:
    macro = '''
#define MARKSVC(code, arg)                                                       \\
  do {                                                                           \\
    *(volatile UINT32 *)(UINTN)0xD7FF0110ULL = ((UINT32)(code) << 24) | ((UINT32)(arg) & 0xFFFFFF); \\
    *(volatile UINT32 *)(UINTN)0xD7FF0114ULL = *(volatile UINT32 *)(UINTN)0xD7FF0114ULL + 1;        \\
  } while (0)
STATIC BOOLEAN mInEbs = FALSE;
'''
    t = t.replace("#define TRACE(...)", macro + "#define TRACE(...)", 1)
    # TRACE becomes silent once EBS started
    t = t.replace("#define TRACE(...)  do { if (mCalls++ < 4000) { DEBUG ((DEBUG_ERROR, __VA_ARGS__)); } } while (0)",
                  "#define TRACE(...)  do { if (!mInEbs && mCalls++ < 4000) { DEBUG ((DEBUG_ERROR, __VA_ARGS__)); } } while (0)")
    codes = {
        "TrHandleProtocol": 1, "TrLocateProtocol": 2, "TrOpenProtocol": 3, "TrLocateHandleBuffer": 4,
        "TrGetMemoryMap": 5, "TrStall": 6, "TrWaitForEvent": 7, "TrCheckEvent": 8, "TrAllocatePages": 9,
        "TrAllocatePool": 10, "TrFreePages": 11, "TrCreateEvent": 12, "TrCreateEventEx": 13, "TrSetTimer": 14,
        "TrSetWatchdog": 15, "TrInstallCfg": 16, "TrConnect": 17, "TrLoadImage": 18, "TrStartImage": 19,
        "TrGetVariable": 20, "TrSetVariable": 21, "TrOutputString": 22, "TrReadKey": 23,
    }
    for name, code in codes.items():
        # find: "\n<name> (" ... first "{" after it
        m = re.search(r"\n%s \(" % name, t)
        if not m:
            print("skip", name)
            continue
        b = t.index("{", m.end())
        arg = "Us" if name == "TrStall" else "0"
        t = t[:b + 1] + "\n  MARKSVC (%d, %s);" % (code, arg) + t[b + 1:]
    # mark EBS entry
    t = t.replace('  DEBUG ((DEBUG_ERROR, "[MUCHAIN] *** ExitBootServices called by the OS loader ***\\n"));',
                  '  mInEbs = TRUE;\n  DEBUG ((DEBUG_ERROR, "[MUCHAIN] *** ExitBootServices called by the OS loader ***\\n"));', 1)
    p.write_text(t, encoding="utf-8")
print("ok", "MARKSVC" in t, t.count("MARKSVC ("))
