// rdmem: read 32-bit registers through /dev/mem with a Device (O_SYNC) mapping.  usage: rdmem <phys_hex>[:<count>] ...
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

int main(int argc, char **argv)
{
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	long pg = sysconf(_SC_PAGESIZE);
	for (int i = 1; i < argc; i++) {
		char *colon;
		uint64_t a = strtoull(argv[i], &colon, 16);
		int n = (*colon == ':') ? atoi(colon + 1) : 1;
		for (int k = 0; k < n; k++) {
			uint64_t p = a + 4ull * k;
			uint64_t base = p & ~(uint64_t)(pg - 1);
			volatile uint32_t *m = mmap(NULL, pg, PROT_READ, MAP_SHARED, fd, base);
			if (m == MAP_FAILED) { printf("%08llx MAPFAIL\n", (unsigned long long)p); continue; }
			uint32_t v = m[(p - base) / 4];
			printf("%08llx %08x\n", (unsigned long long)p, v);
			fflush(stdout);
			munmap((void *)m, pg);
		}
	}
	return 0;
}
