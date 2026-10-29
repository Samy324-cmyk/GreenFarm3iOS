#include <errno.h>
#include <stdint.h>
#include <sys/mount.h>

// Keep the platform struct layout inside its SDK, rather than reproducing a
// Darwin-specific statfs layout in Dart. Dart receives four unsigned values.
__attribute__((visibility("default"))) __attribute__((used))
int32_t gf3_statfs(const char *path, uint64_t *values) {
  if (path == NULL || values == NULL) return EINVAL;
  struct statfs status;
  if (statfs(path, &status) != 0) return errno;
  values[0] = status.f_bsize;
  values[1] = status.f_blocks;
  values[2] = status.f_bavail;
  values[3] = status.f_bfree;
  return 0;
}
