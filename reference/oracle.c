/* Local test adapter; algorithm implementation is the vendored upstream C. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "upstream/permutations.h"

int main(int argc, char **argv) {
  static const uint8_t rc[12] = {
      0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5,
      0x96, 0x87, 0x78, 0x69, 0x5a, 0x4b};
  const int single = argc == 2 && strcmp(argv[1], "round") == 0;
  if (argc != 2 || (!single && strcmp(argv[1], "permutation") != 0)) {
    fprintf(stderr, "usage: %s round|permutation\n", argv[0]);
    return 2;
  }
  unsigned selector;
  char hex[81];
  while (scanf("%u %80s", &selector, hex) == 2) {
    ascon_state_t state;
    if (strlen(hex) != 80) return 3;
    for (unsigned i = 0; i < 5; ++i) {
      char word[17];
      memcpy(word, hex + i * 16, 16);
      word[16] = '\0';
      char *end;
      state.x[i] = strtoull(word, &end, 16);
      if (*end) return 3;
    }
    if (single) {
      if (selector >= 12) return 3;
      ROUND(&state, rc[selector]);
    } else if (selector == 8) {
      P8(&state);
    } else if (selector == 12) {
      P12(&state);
    } else {
      return 3;
    }
    for (unsigned i = 0; i < 5; ++i) printf("%016" PRIx64, state.x[i]);
    putchar('\n');
  }
  return ferror(stdin) ? 4 : 0;
}
