// pcie_replay: on a running Android (Wi-Fi up, link idle) redo MuChain's PCIe0 link bring-up through /dev/mem:
//   PERST low, LTSSM off, BCR pulses, PARF init, PHY sequence, PHY ready, PERST high, DBI setup, LTSSM enable, trace LTSSM.
// If the EP re-trains here the sequence is fine and the Mu failure comes from the environment; if not, the sequence is wrong.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <sys/mman.h>
#include "physeq.h"
#include "crm.h"
static FILE *LF;
#define LOG(...) do { printf(__VA_ARGS__); if (LF) { fprintf(LF, __VA_ARGS__); fflush(LF); fsync(fileno(LF)); } } while (0)

static int fd;
static volatile uint32_t *map(uint64_t phys, size_t len)
{
	void *m = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, phys);
	if (m == MAP_FAILED) { perror("mmap"); exit(1); }
	return m;
}
static volatile uint32_t *TLMM16, *TLMM17, *TLMM18, *TLMM19, *TLMM95, *CRM, *SM;
static volatile uint32_t *PARF, *PHY, *DBI, *GCCV, *GCCP, *GCCQ, *TLMM94;
#define R(b, o) ((b)[(o) / 4])
#define W(b, o, v) do { (b)[(o) / 4] = (v); } while (0)
static void usleep_(unsigned us) { struct timespec t = { us / 1000000, (us % 1000000) * 1000L }; nanosleep(&t, NULL); }
static uint64_t now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000ull + t.tv_nsec / 1000; }
static void ms(unsigned n) { usleep_(n * 1000); }

static void pins(const char *w) { LOG("pins %s: gpio16=%x 17=%x 18=%x 19=%x 94=%x 95=%x'+BS+'n", w, R(TLMM16, 4) & 3, R(TLMM17, 4) & 3, R(TLMM18, 4) & 3, R(TLMM19, 4) & 3, R(TLMM94, 4) & 3, R(TLMM95, 4) & 3); }

static void dump(const char *tag, volatile uint32_t *b, unsigned from, unsigned to) { for (unsigned o = from; o < to; o += 4) { uint32_t v = R(b, o); if (v) LOG("%s %04x %08x\n", tag, o, v); } }

int main(int argc, char **argv)
{
	int lanes_fix = argc > 1 && argv[1][0] == 'x';
	int cycle = argc > 1 && argv[1][0] == 'c';
	int crmrep = argc > 1 && strchr(argv[1], 'm');
	int smrep = argc > 1 && strchr(argv[1], 'p');
	int btlow = argc > 1 && argv[1][0] == 'c' && argv[1][1] == 'b';	/* optional: x -> write PORT_LINK_CTRL x1 like the old Mu */
	setvbuf(stdout, NULL, _IONBF, 0);
	LF = fopen("/data/local/tmp/rm9_replay.log", "w");
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open"); return 1; }
	PARF = map(0x1C00000, 0x2000);
	PHY = map(0x1C06000, 0x2000);
	DBI = map(0x60000000, 0x1000);
	GCCV = map(0x152000, 0x1000);	/* GCC + 0x52000 : votes */
	GCCP = map(0x16B000, 0x1000);	/* GCC + 0x6B000 : pcie_0 */
	GCCQ = map(0x16C000, 0x1000);	/* GCC + 0x6C000 : pcie_0 phy */
	TLMM94 = map(0xF15E000, 0x1000);
	TLMM16 = map(0xF110000, 0x1000);
	TLMM17 = map(0xF111000, 0x1000);
	TLMM18 = map(0xF112000, 0x1000);
	TLMM19 = map(0xF113000, 0x1000);
	TLMM95 = map(0xF15F000, 0x1000);
	CRM = map(0x1D01000, 0x6000);
	SM = map(0x1D07000, 0x2000);

	LOG("before: ltssm=%08x dbi72c=%08x elbi=%08x\n", R(PARF, 0x1B0), R(DBI, 0x72C), R(DBI, 0xF28));
	/* keep the branch clocks on by software votes, as MuChain does */
	W(GCCV, 0x008, R(GCCV, 0x008) | 0x7F);
	W(GCCV, 0x000, R(GCCV, 0x000) | (1u << 12) | (1u << 19) | (1u << 22));
	LOG("step: perst low / ltssm off\n");
	/* PERST low, LTSSM off */
	W(PARF, 0x22C, 0);	/* mask all PARF interrupts first: no linkdown/AER interrupt for the Android driver to react to */
	W(TLMM94, 4, 0);
	W(PARF, 0x1B0, R(PARF, 0x1B0) & ~0x100u);
	ms(100);
	LOG("step: core BCR\n");
	if (smrep) {
		static const uint32_t seq[13] = { 0x1c018081, 0x70074002, 0x50028000, 0x28007003, 0x80804002, 0x70021c01, 0x18001802, 0x70005000, 0x10004000, 0x80814002, 0x18001c01, 0x1c018080, 0x100 };
		static const uint32_t br[7] = { 0x04, 0x1c, 0x24, 0x2c, 0, 0, 0 };
		LOG("step: crm probe + pcie_sm program\n");
		for (unsigned k = 0; k < sizeof(mPcieCrmProbe) / sizeof(mPcieCrmProbe[0]); k++) W(CRM, mPcieCrmProbe[k][0] - 0x1D01000, mPcieCrmProbe[k][1]);
		W(SM, 0x1040, 0); W(SM, 0x1048, 0);
		for (int k = 0; k < 13; k++) W(SM, 4 * k, seq[k]);
		for (int k = 0; k < 7; k++) W(SM, 0x1000 + 4 * k, br[k]);
		W(SM, 0x1090, 1); ms(1);
		LOG("sm: 1078=%x 1080=%x 1088=%x\n", R(SM, 0x1078), R(SM, 0x1080), R(SM, 0x1088));
	}
	if (cycle) { LOG("step: WLAN_EN low 150ms, high\n"); if (btlow) { LOG("BT_EN low\n"); W(TLMM17, 4, 0); } pins("before cycle"); W(TLMM16, 4, 0); ms(150); pins("WLAN_EN low"); W(TLMM16, 4, 2); ms(2); pins("WLAN_EN +2ms"); ms(20); pins("WLAN_EN +22ms"); if (crmrep) { LOG("step: crm pwr tables\n"); for (unsigned k = 0; k < sizeof(mPcieCrmPwr) / sizeof(mPcieCrmPwr[0]); k++) { uint32_t pa = mPcieCrmPwr[k][0]; W(CRM, pa - 0x1D01000, mPcieCrmPwr[k][1]); if (pa == 0x1D02020) { uint32_t s0 = R(CRM, 0x1000), s1 = s0; int w; for (w = 0; w < 100 && s1 == s0; w++) { usleep_(100); s1 = R(CRM, 0x1000); } LOG("crm switch -> %u: %08x -> %08x after %d x100us\n", mPcieCrmPwr[k][1], s0, s1, w); } } } ms(8); }
	/* core + link-down BCR pulse */
	W(GCCP, 0x000, 1); W(GCCQ, 0x014, 1); ms(1); W(GCCP, 0x000, 0); W(GCCQ, 0x014, 0); ms(1);
	LOG("step: parf\n");
	dump("RPARF", PARF, 0, 0x700);
	dump("RDBI", DBI, 0, 0x900);
	/* PARF */
	W(PARF, 0x1000, 4); W(PARF, 0x20, 0); W(PARF, 0x40, 0x900); W(PARF, 0x350, 0); W(PARF, 0x0, 0x365E); W(PARF, 0x174, 0x13);
	W(PARF, 0x22C, 0); W(PARF, 0x22C, 0x7F80D202); W(PARF, 0x358, 0x4000000); W(PARF, 0x1A8, 0x80000014);
	LOG("step: phy bcr + seq\n");
	/* PHY: BCR pulse, pipe mux, sequence */
	W(GCCQ, 0x01C, 1); ms(1); W(GCCQ, 0x01C, 0); ms(1);
	dump("RPHY", PHY, 0, 0x1400);
	W(GCCP, 0x070, 0);
	for (unsigned i = 0; i < sizeof(mPciePhySeq) / sizeof(mPciePhySeq[0]); i++) {
		W(PHY, mPciePhySeq[i][0], mPciePhySeq[i][1]);
		if (mPciePhySeq[i][2]) usleep_(mPciePhySeq[i][2]);
	}
	uint64_t t0 = now_us(); int ready = 0;
	while (now_us() - t0 < 200000) { if (!(R(PHY, 0x214) & (1u << 6))) { ready = 1; break; } }
	LOG("phy ready=%d status=%02x after %lluus\n", ready, R(PHY, 0x214), (unsigned long long)(now_us() - t0));
	ms(10);
	W(PARF, 0x2C4, 0x68); W(PARF, 0x2C4, 0x168);
	W(DBI, 0x714, 0x8000020);
	W(TLMM94, 4, 2);	/* PERST released */
	ms(1);
	W(DBI, 0x8BC, R(DBI, 0x8BC) | 1);
	if (lanes_fix) W(DBI, 0x710, (R(DBI, 0x710) & ~(0x3Fu << 16)) | (1u << 16));
	W(DBI, 0x80C, 0x130190); W(DBI, 0x890, 0x2001); W(DBI, 0x8A8, 0xC000060); W(DBI, 0x890, 0x2000);
	W(DBI, 0x8AC, 0x155A0); W(DBI, 0x8BC, 0x5BF41); W(DBI, 0x154, 0x55555555); W(DBI, 0x8BC, 0x5BF40);
	W(DBI, 0xA0, 0x10041); W(DBI, 0x78, 0x105810);
	dump("BPARF", PARF, 0, 0x700);
	dump("BDBI", DBI, 0, 0x900);
	dump("BPHY", PHY, 0, 0x1400);
	W(PARF, 0x1B0, 0x100);	/* LTSSM enable */
	uint32_t last = 0xffffffff; uint64_t s = now_us(); int logged = 0;
	while (now_us() - s < 300000 && logged < 40) {
		uint32_t cur = R(PARF, 0x1B0) & 0x3F;
		if (cur != last) { LOG("+%lluus ltssm=%02x dbg1=%08x\n", (unsigned long long)(now_us() - s), cur, R(DBI, 0x72C)); last = cur; logged++; }
		uint32_t d = R(DBI, 0x72C);
		if ((d & 0x10) && !(d & (1u << 29))) { pins("link up"); LOG("LINK UP dbg1=%08x elbi=%08x lnksta=%08x\n", d, R(DBI, 0xF28), R(DBI, 0x80)); break; }
	}
	LOG("end: ltssm=%08x dbi72c=%08x\n", R(PARF, 0x1B0), R(DBI, 0x72C));
	return 0;
}
