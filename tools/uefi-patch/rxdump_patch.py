p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
old = '''        PL ("  %04x: %08x %08x %08x %08x %08x %08x %08x %08x''' + BS + '''n", K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
      }
    }
'''
assert old in s
new = old + '''    {
      UINT32  Sz3, K;
      UINT8   *R = SmemItem (2, 480, &Sz3);
      if (R != NULL && D2 != NULL) {
        UINT32  RHead = D2[3];
        PL ("GLINK rx fifo (item 480) 0..0x%x:''' + BS + '''n", RHead);
        for (K = 0; K < RHead && K < 0x800; K += 32) {
          UINT32  *W = (UINT32 *)(R + K);
          PL ("  r%04x: %08x %08x %08x %08x %08x %08x %08x %08x''' + BS + '''n", K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
        }
      }
    }
'''
i = s.index(old)
# replace the first occurrence block
j = s.index('''    }
''', i + len(old) - 7)
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
