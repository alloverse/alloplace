#include <string.h>
#include <ei.h>
#include <allonet/allonet.h>
#include <allonet/../../lib/cJSON/cJSON.h>
#include "erl_comm.h"
#include <enet/enet.h>
#include <sys/fcntl.h>
#include <assert.h>

///////// UTILS

void free_handle(uint8_t **handle) { free(*handle); }
#define scoped __attribute__ ((__cleanup__(free_handle)))
void free_x(ei_x_buff *handle) { ei_x_free(handle); }
#define scopedx __attribute__ ((__cleanup__(free_x)))
void free_j(cJSON **handle) { cJSON_Delete(*handle); }
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

cJSON *ei_decode_as_cjson(uint8_t *buf, int *index)
{
    const char* s = buf + *index;
    int arity;
    double vf;
    char c = get8(s, index);
    cJSON *ret = NULL;

    switch (c) {
    case ERL_SMALL_INTEGER_EXT:
        ret = cJSON_CreateNumber(get8(s, index));
        break;
    case ERL_INTEGER_EXT:
        ret = cJSON_CreateNumber(get32be(s, index));
        break;
    case ERL_FLOAT_EXT:
    case NEW_FLOAT_EXT:
        assert(ei_decode_double(buf, index, &vf) == 0);
        ret = cJSON_CreateNumber(vf);
        break;
    case ERL_ATOM_EXT:
    case ERL_ATOM_UTF8_EXT:
    case ERL_SMALL_ATOM_EXT:
    case ERL_SMALL_ATOM_UTF8_EXT: {
        char command[MAXATOMLEN];
	    assert(ei_decode_atom(buf, index, command) == 0);
        ret= cJSON_CreateString(command); 
        break; }
    case ERL_SMALL_TUPLE_EXT:
    case ERL_LARGE_TUPLE_EXT:
        arity = (c == ERL_SMALL_TUPLE_EXT) ? get8(s, index) : get32be(s, index);
        ret = cJSON_CreateArray();
        for(int i = 0; i < arity; i++) {
            cJSON *child = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToArray(ret, child);
        }
        break;
    case ERL_NIL_EXT:
        ret = cJSON_CreateNull();
        break;
    case ERL_STRING_EXT: {
	    arity = get16be(s, index);
        char s[arity];
        assert(ei_decode_string(buf, index, s) == 0);
        ret = cJSON_CreateString(s); 
        break; }
    case ERL_LIST_EXT:
        arity = get32be(s, index);
        ret = cJSON_CreateArray();
        for(int i = 0; i < arity; i++) {
            cJSON *child = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToArray(ret, child);
        }
        break;
    case ERL_MAP_EXT:
        arity = get32be(s, index);
        ret = cJSON_CreateObject();
        for(int i = 0; i < arity; i++) {
            cJSON *key = ei_decode_as_cjson(buf, index);
            assert(cJSON_IsString(key));
            cJSON *value = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToObject(ret, key->valuestring, value);
        }
        break;
    }
    assert(ret != NULL && "unsupported type");
    return ret;
}

////////// STATE MANAGEMENT AND HANDLER FUNCTIONS

allo_state state;
static void add_entity(cJSON *json, ei_x_buff response)
{
    printf("It'd be great to add this entity now: %s\n", cJSON_Print(json));
}

///////// COMMS MANAGEMENT

void handle_erl()
{
    scoped uint8_t *request = read_cmd();
    int request_index = 0;
    if(!request)
        return;

    int erlversion;
    int tupleCount;
    assert(ei_decode_version(request, &request_index, &erlversion) == 0);
    assert(ei_decode_tuple_header(request, &request_index, &tupleCount) == 0);
    
    char command[MAXATOMLEN];
    long reqId;
    assert(ei_decode_atom(request, &request_index, command) == 0);
    assert(ei_decode_long(request, &request_index, &reqId) == 0);
    
    scopedx ei_x_buff response; ei_x_new_with_version(&response);
    if(strcmp(command, "ping") == 0) {
        ei_x_format_wo_ver(&response, "{response, ~l, statepong}", reqId);
    } else if(strcmp(command, "add_entity") == 0) {
        cJSON *json = ei_decode_as_cjson(request, &request_index);
        add_entity(json, response);
    } else {
        printf("statedaemon: Unknown command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"no such command\"}}", reqId);
    }
    if(response.index == 0) {
        printf("statedaemon: Missing response to command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"missing response\"}}", reqId);        
    }

    write_cmd(response.buff, response.index);
}

int main()
{
    if(!allo_initialize(false)) {
        fprintf(stderr, "Unable to initialize allostate");
        return -1;
    }

    ei_init();

    if(fcntl(erlin, F_SETFL, O_NONBLOCK) != 0) {
        perror("failed to set erlin as non-blocking");
        return -4;
    }
    
    printf("allostateport open as %d\n", getpid());
    
    while (1) {
        ENetSocketSet set;
        ENET_SOCKETSET_EMPTY(set);
        ENET_SOCKETSET_ADD(set, erlin);
        
        int selectr = enet_socketset_select(erlin, &set, NULL, 100);
        if(selectr < 0) {
            perror("select failed, terminating");
            return -3;
        } else if(ENET_SOCKETSET_CHECK(set, erlin)) {
            handle_erl();
        }
    }
    return 0;
}
