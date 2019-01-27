#include <stdint.h>

static const int erlin = 3;
static const int erlout = 4;

// tries to read a command from erlin, assuming it's a nonblocking fd.
// returns NULL if a full command was not available.
uint8_t * read_cmd();

// writes a full command to erlout, assuming it's a blocking fd.
// returns < 0 on error.
int write_cmd(uint8_t *buf, int len);
