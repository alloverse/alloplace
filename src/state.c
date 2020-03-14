#include <string.h>
#include <ei.h>
#include <allonet/allonet.h>
#include "erl_comm.h"
#include <enet/enet.h>
#include <sys/fcntl.h>
#include <assert.h>

 #define MAX(a,b) \
   ({ __typeof__ (a) _a = (a); \
       __typeof__ (b) _b = (b); \
     _a > _b ? _a : _b; })

void free_handle(uint8_t **handle) { free(*handle); }
#define scoped __attribute__ ((__cleanup__(free_handle)))
void free_x(ei_x_buff *handle) { ei_x_free(handle); }
#define scopedx __attribute__ ((__cleanup__(free_x)))

void write_term(ei_x_buff term)
{
    write_cmd(term.buff, term.index);
}

void handle_erl()
{
    scoped uint8_t *buf = read_cmd();
    int bufindex = 0;
    if(!buf)
        return;

    int erlversion;
    int tupleCount;
    assert(ei_decode_version(buf, &bufindex, &erlversion) == 0);
    assert(ei_decode_tuple_header(buf, &bufindex, &tupleCount) == 0);
    
    char command[MAXATOMLEN];
    long reqId;
    assert(ei_decode_atom(buf, &bufindex, command) == 0);
    assert(ei_decode_long(buf, &bufindex, &reqId) == 0);
    
    scopedx ei_x_buff msg; ei_x_new_with_version(&msg);
    if(strcmp(command, "ping") == 0) {
        ei_x_format_wo_ver(&msg, "{response, ~l, statepong}", reqId);
    } else {
        ei_x_format_wo_ver(&msg, "{response, ~l, {error, \"no such command\"}}", reqId);
    }

    write_cmd(msg.buff, msg.index);
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
        
        int selectr = enet_socketset_select(MAX(0, erlin), &set, NULL, 100);
        if(selectr < 0) {
            perror("select failed, terminating");
            return -3;
        } else if(ENET_SOCKETSET_CHECK(set, erlin)) {
            handle_erl();
        }
    }
    return 0;
}
