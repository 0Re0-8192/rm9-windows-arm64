# first smoke test of rm9io: read well-known registers (all of them are read-only looks at state that Mu/Windows already touched)
. S:\rm9\rm9io.ps1
'GSNPSID (expect 33313130): ' + ('{0:X8}' -f (Rm9Read 0xA60C120 1)[0])
Rm9Dump 0xA6F8800 32 'QSCRATCH'
Rm9Dump 0xA60C700 8 'DWC3 DCFG/DCTL/DEVTEN/DSTS'
Rm9Dump 0x88E3130 4 'eUSB2 PHY +0x130'
Rm9Dump 0x139000 8 'GCC USB30_PRIM GDSC area'
