p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'

a = s.index('// one full-duplex transfer of Len (<= 64) bytes with chip select held for the whole transfer')
b = s.index('// Goodix BRL-D frames: WRITE = F0')
new = r'''// SE4 has its FIFO interface disabled (GENI_IF_DISABLE_RO bit0 = 1: the SE is meant for GSI/GPI use), so use the serial engine's own DMA (geni_se_select_dma_mode + geni_se_tx/rx_init_dma, as spi-geni-qcom
// does for transfers with sg lists): buffers are plain physical addresses (UEFI is identity mapped), cache lines are cleaned/invalidated by hand.
STATIC UINT8  mDmaTx[128] __attribute__ ((aligned (64)));
STATIC UINT8  mDmaRx[128] __attribute__ ((aligned (64)));

STATIC VOID
GeniCacheOp (IN VOID *Buf, IN UINT32 Len)
{
  UINT64  A = (UINT64)(UINTN)Buf & ~63ULL, E = (UINT64)(UINTN)Buf + Len;

  for (; A < E; A += 64) {
    __asm__ volatile ("dc civac, %0" : : "r" (A) : "memory");
  }
  __asm__ volatile ("dsb sy" : : : "memory");
}

STATIC BOOLEAN
GeniSpiXfer (IN CONST UINT8 *Tx, OUT UINT8 *Rx, IN UINT32 Len)
{
  UINT32  I, T, Td = 0, Rd = 0, M = 0;

  if (Len == 0 || Len > 64) {
    return FALSE;
  }
  for (I = 0; I < 128; I++) {
    mDmaTx[I] = I < Len ? Tx[I] : 0;
    mDmaRx[I] = 0xEE;
  }
  GeniCacheOp (mDmaTx, 128);
  GeniCacheOp (mDmaRx, 128);
  // geni_se_select_dma_mode(): irq clear, mask the FIFO interrupts, DMA mode on
  SE_W (0xE18, 0);
  SE_W (0x618, 0xFFFFFFFF);
  SE_W (0x648, 0xFFFFFFFF);
  SE_W (0xC44, 0xFFFFFFFF);
  SE_W (0xD44, 0xFFFFFFFF);
  SE_W (0xE1C, 0xFFFFFFFF);
  SE_W (0x614, SE_R (0x614) & ~(0x1U | 0x40000000U | 0x4000000U | 0x8000000U));
  SE_W (0x258, SE_R (0x258) | 1U);
  SE_W (0x26C, Len);
  SE_W (0x270, Len);
  SE_W (0x600, 3U << 27);                                       // SPI_TX_ONLY | SPI_RX_ONLY
  // geni_se_rx_init_dma() then geni_se_tx_init_dma()
  SE_W (0xD4C, 7);
  SE_W (0xD30, (UINT32)(UINTN)mDmaRx);
  SE_W (0xD34, (UINT32)(((UINT64)(UINTN)mDmaRx) >> 32));
  SE_W (0xD38, 0);
  SE_W (0xD3C, Len);
  SE_W (0xC4C, 7);
  SE_W (0xC30, (UINT32)(UINTN)mDmaTx);
  SE_W (0xC34, (UINT32)(((UINT64)(UINTN)mDmaTx) >> 32));
  SE_W (0xC38, 1);                                              // EOT buffer
  SE_W (0xC3C, Len);
  for (T = 0; T < 20000; T++) {                                 // ~200 ms
    Td |= SE_R (0xC40);
    Rd |= SE_R (0xD40);
    M |= SE_R (0x610);
    if ((Td & 4) != 0 || (Rd & 4) != 0 || (M & 0x3300003EU) != 0) {
      PL ("GENI: dma error tx=0x%x rx=0x%x m_irq=0x%x%a", Td, Rd, M, "\n");
      break;
    }
    if ((Td & 1) != 0 && (Rd & 1) != 0) {
      break;
    }
    gBS->Stall (10);
  }
  if ((Td & 1) == 0 || (Rd & 1) == 0) {
    PL ("GENI: dma timeout/err: tx_stat=0x%x rx_stat=0x%x m_irq=0x%x status=0x%x tx_len_in=%u rx_len_in=%u%a", Td, Rd, M, SE_R (0x40), SE_R (0xC54), SE_R (0xD54), "\n");
    SE_W (0x604, 4U);                                           // cancel
    gBS->Stall (2000);
    SE_W (0xC58, 1);                                            // TX/RX FSM reset
    SE_W (0xD58, 1);
    gBS->Stall (2000);
    SE_W (0x618, 0xFFFFFFFF);
    SE_W (0xC44, 0xFFFFFFFF);
    SE_W (0xD44, 0xFFFFFFFF);
    return FALSE;
  }
  for (T = 0; T < 1000 && (SE_R (0x610) & 1U) == 0; T++) {      // command done (CS released)
    gBS->Stall (10);
  }
  SE_W (0x618, 0xFFFFFFFF);
  SE_W (0xC44, 0xFFFFFFFF);
  SE_W (0xD44, 0xFFFFFFFF);
  GeniCacheOp (mDmaRx, 128);
  for (I = 0; I < Len; I++) {
    Rx[I] = mDmaRx[I];
  }
  return TRUE;
}

'''
s = s[:a] + new + s[b:]
# dump the IF registers too
old = 'MMR (0x00AC0004ULL), "' + BS + 'n");'
assert old in s
s = s.replace(old, 'MMR (0x00AC0004ULL), "' + BS + 'n");\n  PL ("GENI: dma_if_en_ro=0x%08x se_fifo_if_disable=0x%08x se_dma_if_en=0x%08x%a", SE_R (0xE20), SE_R (0x2008), SE_R (0x2004), "' + NL + '");', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
