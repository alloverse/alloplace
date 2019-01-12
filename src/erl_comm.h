#include <stdint.h>

int read_cmd(uint8_t *buf);
int write_cmd(uint8_t *buf, int len);
int read_exact(uint8_t *buf, int len);
int write_exact(uint8_t *buf, int len);