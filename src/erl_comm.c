#include <unistd.h>
#include "erl_comm.h"

int read_cmd(uint8_t *buf)
{
  int len;

  if (read_exact(buf, 2) != 2)
    return(-1);
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
