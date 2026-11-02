p = '<RM9_WORKDIR>/drv/rm9io/rm9io.c'
s = open(p, encoding='utf-8', newline='').read()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')

# 1. struct: drop the pad, add a register snapshot taken at the last failure
old = '    UINT8  Pad[2];\n} RM9_TOUCH_OUT;'
assert old in s
s = s.replace(old, '''    UINT8  Pad[2];
    UINT32 Reinits;      // SE re-initialisations done by the poller
    UINT32 Diag[12];     // SE registers at the last failure: status 0x40, clk_ctrl 0x60, if_dis 0x64, m_irq 0x610, m_cmd 0x600, dma_mode 0x258, ser_m_clk 0x48, tx_st 0xC40, rx_st 0xD40, tx_len 0xC54, rx_len 0xD54, tx_trans 0x26C
} RM9_TOUCH_OUT;''', 1)

# 2. SE re-init (port of MuChain GeniSpiInit, 19.2 MHz / 1 = 9.6 MHz SPI clock) + failure snapshot, placed before GeniXfer
a = 'static BOOLEAN GeniXfer('
assert a in s
init = r'''static VOID SeSnapshot(VOID)
{
    g_Touch.Diag[0] = SE_RD(0x40);  g_Touch.Diag[1] = SE_RD(0x60);  g_Touch.Diag[2] = SE_RD(0x64);  g_Touch.Diag[3] = SE_RD(0x610);
    g_Touch.Diag[4] = SE_RD(0x600); g_Touch.Diag[5] = SE_RD(0x258); g_Touch.Diag[6] = SE_RD(0x48);  g_Touch.Diag[7] = SE_RD(0xC40);
    g_Touch.Diag[8] = SE_RD(0xD40); g_Touch.Diag[9] = SE_RD(0xC54); g_Touch.Diag[10] = SE_RD(0xD54); g_Touch.Diag[11] = SE_RD(0x26C);
}

// cancel / abort whatever the SE is doing, reset the DMA state machines, then redo geni_se_init + spi_geni_init (as MuChain GeniSpiInit)
static VOID SeReinit(VOID)
{
    ULONG T, Depth;
    SE_WR(0x604, 4U);                                    // M cancel
    for (T = 0; T < 1000 && !(SE_RD(0x610) & 0x10U); T++) { KeStallExecutionProcessor(10); }
    if (!(SE_RD(0x610) & 0x10U)) {
        SE_WR(0x604, 2U);                                // M abort
        for (T = 0; T < 1000 && !(SE_RD(0x610) & 0x20U); T++) { KeStallExecutionProcessor(10); }
    }
    SE_WR(0xC58, 1);
    SE_WR(0xD58, 1);
    KeStallExecutionProcessor(2000);
    SE_WR(0xE18, 0);
    SE_WR(0x618, 0xFFFFFFFF);
    SE_WR(0x648, 0xFFFFFFFF);
    SE_WR(0xC44, 0xFFFFFFFF);
    SE_WR(0xD44, 0xFFFFFFFF);
    SE_WR(0xE1C, 0xFFFFFFFF);
    SE_WR(0x28, SE_RD(0x28) | 0x7F);
    SE_WR(0xE30, SE_RD(0xE30) | 0xF);
    SE_WR(0x24, 0x7F);
    SE_WR(0x20, 1);
    SE_WR(0x258, SE_RD(0x258) & ~1U);
    Depth = (SE_RD(0xE24) >> 16) & 0x3F;
    if (Depth < 4) { Depth = 16; }
    SE_WR(0x810, Depth - 3);
    SE_WR(0x814, Depth - 2);
    SE_WR(0x614, SE_RD(0x614) | 0x7FC0007F);
    SE_WR(0x644, SE_RD(0x644) | 0x3E | 0x3E00 | 0x3000000);
    SE_WR(0x22C, 0);
    SE_WR(0x250, 0);
    SE_WR(0x224, 0);
    SE_WR(0x230, 0);
    SE_WR(0x24C, 0);
    SE_WR(0x25C, SE_RD(0x25C) & ~2U);
    SE_WR(0x260, 0x7F8FE);
    SE_WR(0x264, 0xFFEFE);
    SE_WR(0x284, 0x7F8FE);
    SE_WR(0x288, 0xFFEFE);
    SE_WR(0x254, 0);
    SE_WR(0x268, 4);
    SE_WR(0x7C, 0);
    SE_WR(0x48, (1U << 4) | 1U);
    g_Touch.Reinits++;
}

'''
s = s.replace(a, init + a, 1)

# 3. failure path: snapshot before the cancel
old = '        g_Touch.LastTd = Td; g_Touch.LastRd = Rd; g_Touch.LastM = M;\n'
assert old in s
s = s.replace(old, old + '        SeSnapshot();\n', 1)

# 4. thread: initial re-init, re-init every 20 consecutive failures
old = '    Dly.QuadPart = -50000;      // 5 ms\n'
assert old in s
s = s.replace(old, old + '    SeReinit();\n', 1)
old = '        if (!GoodixRd(0x10308, F, 26)) {\n            g_Touch.Errors++;\n'
assert old in s
s = s.replace(old, old + '            if ((g_Touch.Errors % 20) == 0) {\n                SeReinit();\n            }\n', 1)
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
