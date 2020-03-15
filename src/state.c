#include <string.h>
#include <enet/enet.h>
#include <sys/fcntl.h>
#include <assert.h>

#include <allonet/allonet.h>
#include "erl_comm.h"
#include "util.h"


////////// STATE MANAGEMENT AND HANDLER FUNCTIONS

allo_state state;
static void add_entity(cJSON *json, ei_x_buff *response)
{
    const char *entity_id = cJSON_GetObjectItem(json, "id")->valuestring;
    printf("Adding entity %s\n", entity_id);
    allo_entity *ent = entity_create(entity_id);
    cJSON *components = cJSON_DetachItemFromObject(json, "components");
    ent->components = components;
    LIST_INSERT_HEAD(&state.entities, ent, pointers);

    ei_x_encode_atom(response, "ok");
}

///////// COMMS MANAGEMENT
 
void handle_erl()
{
    scoped char *request = (char*)read_cmd();
    int request_index = 0;
    if(!request)
        return;

    int erlversion;
    int tupleCount;
    assert(ei_decode_version(request, &request_index, &erlversion) == 0);
    assert(ei_decode_tuple_header(request, &request_index, &tupleCount) == 0);
    
    char command[MAXATOMLEN];
    long reqId;
    int argsLen;
    assert(ei_decode_atom(request, &request_index, command) == 0);
    assert(ei_decode_long(request, &request_index, &reqId) == 0);
    assert(ei_decode_tuple_header(request, &request_index, &argsLen) == 0);
    
    scopedx ei_x_buff response; ei_x_new_with_version(&response);
    if(strcmp(command, "ping") == 0) {
        ei_x_format_wo_ver(&response, "{response, ~l, statepong}", reqId);
    } else if(strcmp(command, "add_entity") == 0) {
        cJSON *json = ei_decode_cjson_string(request, &request_index);
        add_entity(json, &response);
    } else {
        printf("statedaemon: Unknown command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"no such command\"}}", reqId);
    }
    if(response.index == 0) {
        printf("statedaemon: Missing response to command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"missing response\"}}", reqId);        
    }

    write_cmd((uint8_t*)response.buff, response.index);
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
