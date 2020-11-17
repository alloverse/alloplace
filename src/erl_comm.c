#include <unistd.h>
#include <stdlib.h>
#include "erl_comm.h"
#include <assert.h>
#include <stdio.h>

static uint8_t *g_buf; // buffer between call to handle async reading
static uint32_t g_target_length; // how much to read from stream before done
static uint32_t g_filled_length; // how much read so far

uint8_t* read_inner();
int write_exact(uint8_t *buf, size_t len);

uint8_t* read_cmd()
{
    if(!g_target_length) {
        uint8_t lenbuf[4];
        int bytes_read = read(erlin, lenbuf, 4);
        if(bytes_read != 4) { fprintf(stderr, "couldn't read packet size: only got %d bytes, expected 4\n", bytes_read); }
        assert(bytes_read == 4 && "gotta be able to read full packet size");
        g_target_length = (lenbuf[0] << 24) | (lenbuf[1] << 16) | (lenbuf[2] << 8) | lenbuf[3];
        g_buf = malloc(g_target_length);
    }
    return read_inner();
}

int write_cmd(uint8_t *buf, size_t len)
{
    assert(len < UINT32_MAX);
    uint8_t li[4];
    li[0] = (len >> 24) & 0xff;
    li[1] = (len >> 16) & 0xff;
    li[2] = (len >> 8) & 0xff;
    li[3] = (len) & 0xff;
    write_exact(li, 4);

    return write_exact(buf, len);
}

uint8_t* read_inner()
{
    int bytes_read = read(erlin, g_buf+g_filled_length, g_target_length-g_filled_length);
    assert(bytes_read >= 0);
    g_filled_length += bytes_read;
    if(g_filled_length < g_target_length) {
        return NULL;
    }
    g_target_length = 0;
    g_filled_length = 0;
    uint8_t *ret = g_buf;
    g_buf = NULL;
    return ret;
}

int write_exact(uint8_t *buf, size_t len)
{
  int i, wrote = 0;

  do {
    if ((i = write(erlout, buf+wrote, len-wrote)) <= 0)
      return (i);
    wrote += i;
  } while (wrote<len);

  return len;
}


#include <execinfo.h>
#include <signal.h>
static char g_process_name[255];
static void crash_handler(int sig) {
  void *array[255];
  size_t size;

  // get void*'s for all entries on the stack
  size = backtrace(array, 255);

  // print out all the frames to stderr
  fprintf(stderr, "%s crashed: signal %d:\n", g_process_name, sig);
  backtrace_symbols_fd(array, size, STDERR_FILENO);
  exit(1);
}

void install_crash_handler(const char *process_name)
{
  snprintf(g_process_name, 255, "%s", process_name);
  signal(SIGSEGV, crash_handler);
}