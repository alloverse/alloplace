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

// Decodes a utf8 binary at index and parses it as json
extern cJSON *ei_decode_cjson_string(const char *buf, int *index);
// Decodes arbitrary erlang terms at index into roughly equivalent json. BROKEN
extern cJSON *ei_decode_to_cjson(const char *buf, int *index);

#endif