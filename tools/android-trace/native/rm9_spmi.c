// rm9_spmi: write one PMIC register through the SPMI arbiter channels of EE0 via /dev/mem (same as MuChain's SpmiWriteByte).
//   usage: rm9_spmi <sid> <addr16-hex> <val-hex>        or   rm9_spmi r <sid> <addr16-hex>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
static int fd;
static volatile uint32_t *map(uint64_t p, size_t n) { void *m = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_SHARED, fd, p); if (m == MAP_FAILED) { perror("mmap"); exit(1); } return m; }
int main(int argc, char **argv)
{
	int rd = argc > 1 && argv[1][0] == 'r';
	int a = rd ? 2 : 1;
	if (argc < a + 2) { fprintf(stderr, "usage\n"); return 2; }
	unsigned sid = strtoul(argv[a], 0, 16), addr = strtoul(argv[a + 1], 0, 16), val = rd ? 0 : strtoul(argv[a + 2], 0, 16);
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	volatile uint32_t *core = map(0x0C400000, 0x4000), *cnfg = map(0x0C42D000, 0x1000);
	unsigned ppid = (sid << 8) | (addr >> 8), apid = 0;
	for (unsigned i = 0; i < 1024; i++) {
		uint32_t v = core[(0x2000 + 4 * i) / 4];
		if (((v >> 8) & 0xFFF) == ppid && (cnfg[i] & 7) == 0) { apid = i + 1; break; }
	}
	if (!apid) { printf("no EE0-owned apid for ppid %03x\n", ppid); return 1; }
	apid--;
	if (rd) {
		volatile uint32_t *o = map(0x0C440000 + 0x20ull * apid & ~0xFFFull, 0x1000);
		unsigned off = (0x20 * apid) & 0xFFF;
		o[(off + 0) / 4] = (1u << 27) | ((addr & 0xFF) << 4) | 0;
		uint32_t st = 0; for (int i = 0; i < 1000; i++) { st = o[(off + 8) / 4]; if (st & 1) break; usleep(1); }
		printf("read sid=%x addr=%04x st=%x val=%02x\n", sid, addr, st, o[(off + 0x18) / 4] & 0xFF);
		return 0;
	}
	volatile uint32_t *c = map(0x0C500000 + 0x1000ull * apid, 0x1000);
	c[0x10 / 4] = val;
	c[0] = (0u << 27) | ((addr & 0xFF) << 4) | 0;
	uint32_t st = 0; for (int i = 0; i < 1000; i++) { st = c[8 / 4]; if (st & 1) break; usleep(1); }
	printf("write sid=%x addr=%04x val=%02x apid=%u status=%x\n", sid, addr, val, apid, st);
	return (st & 1) && !(st & 0xE) ? 0 : 1;
}
