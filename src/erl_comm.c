#include <unistd.h>
#include <stdlib.h>
#include "erl_comm.h"
#include <assert.h>
#include <stdio.h>

static uint8_t *g_buf; // buffer between call to handle async reading
static uint16_t g_target_length; // how much to read from stream before done
static uint16_t g_filled_length; // how much read so far

uint8_t* read_inner();
int write_exact(uint8_t *buf, int len);

uint8_t* read_cmd()
{
    if(!g_target_length) {
        uint8_t lenbuf[2];
        if (read(erlin, lenbuf, 2) != 2)
            assert(0);
        g_target_length = (lenbuf[0] << 8) | lenbuf[1];
        g_buf = malloc(g_target_length);
    }
    return read_inner();
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

uint8_t* read_inner()
{
    int bytes_read = read(erlin, g_buf+g_filled_length, g_target_length-g_filled_length);
    assert(bytes_read >= 0);
    g_filled_length += bytes_read;
    if(g_filled_length < g_target_length)
        return NULL;
    
    g_target_length = 0;
    g_filled_length = 0;
    uint8_t *ret = g_buf;
    g_buf = NULL;
    return ret;
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
