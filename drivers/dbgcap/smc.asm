; smc.asm - GhSmc(fn, a1, a2, a3): the same "smc #0" with x0 = function id that MuChain's ArmCallSmc uses (GH_WDT_* calls).  Returns x0.
        AREA |.text|, CODE, READONLY, ALIGN=4
        EXPORT GhSmc
GhSmc   PROC
        smc     #0
        ret
        ENDP
        END
