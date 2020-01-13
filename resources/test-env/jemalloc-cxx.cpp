#include <jemalloc/jemalloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>

using namespace std;

int
main() {
	void *data;
	int ret = posix_memalign(&data, 1024, 32);
	if (ret == 0) {
		// Perform an arbitrary I/O operation to
		// ensure that the compiler doesn't optimize
		// away the posix_memalign() call.
		FILE *f;

		f = fopen("/dev/zero", "w");
		if (f != NULL) {
			fread(data, 1, 1, f);
			fclose(f);
		}

		f = fopen("/dev/null", "w");
		if (f != NULL) {
			fwrite(data, 1, 1, f);
			fclose(f);
		}
	} else {
		perror("posix_memalign() failed");
	}
	return 0;
}
