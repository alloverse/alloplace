#include <unistd.h>
#include "erl_comm.h"

static uint8_t *g_buf; // buffer between call to handle async reading
static uint16_t g_target_length; // how much to read from stream before done
static uint16_t g_filled_length; // how much read so far


uint8_t* read_cmd()
{
    uint8_t lenbuf[2];
    int len;

    if (read_exact(lenbuf, 2) != 2)
        return NULL;
    len = (buf[0] << 8) | buf[1];
    return read_exact(buf, len);
}

int write_cmd(uint8_t *buf, int len)
{
  uint8_t li;

  li = (len >> 8) & 0xff;
  write_exact(&li, 1);
  
  li = len & 0xff;
  write_exact(&li, 1);

  return write_exact(buf, len);
}

int read_exact(uint8_t *buf, int len)
{
  int i, got=0;

  do {
    if ((i = read(erlin, buf+got, len-got)) <= 0)
      return(i);
    got += i;
  } while (got<len);

  return len;
}

int write_exact(uint8_t *buf, int len)
{
  int i, wrote = 0;

  do {
    if ((i = write(erlout, buf+wrote, len-wrote)) <= 0)
      return (i);
    wrote += i;
  } while (wrote<len);

  return len;
}
