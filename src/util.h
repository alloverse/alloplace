#ifndef UTIL__H
#define UTIL__H
#include <allonet/../../lib/cJSON/cJSON.h>
#include <ei.h>
#include <stdlib.h>

static void free_handle(char **handle) { free(*handle); }
#define scoped __attribute__ ((__cleanup__(free_handle)))
static void free_x(ei_x_buff *handle) { ei_x_free(handle); }
#define scopedx __attribute__ ((__cleanup__(free_x)))
static void free_j(cJSON **handle) { cJSON_Delete(*handle); }
#define scopedj __attribute__ ((__cleanup__(free_j)))

#define get8(s, index) \
     ((s) += 1, *index += 1, \
      ((unsigned char *)(s))[-1] & 0xff)
#define get16be(s, index) \
     ((s) += 2, *index += 2, \
      (((((unsigned char *)(s))[-2] << 8) | \
	((unsigned char *)(s))[-1])) & 0xffff) 
#define get32be(s, index) \
     ((s) += 4, *index += 4, \
      ((((unsigned char *)(s))[-4] << 24) | \
       (((unsigned char *)(s))[-3] << 16) | \
       (((unsigned char *)(s))[-2] << 8) | \
       ((unsigned char *)(s))[-1]))

extern cJSON *ei_decode_as_cjson(const char *buf, int *index);

#endif