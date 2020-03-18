#include <string.h>
#include <enet/enet.h>
#include <sys/fcntl.h>
#include <assert.h>

#include <allonet/allonet.h>
#include "erl_comm.h"
#include "util.h"
#include "allonet/src/util.h"


////////// STATE MANAGEMENT AND HANDLER FUNCTIONS

allo_state state;

static void add_entity(long reqId, cJSON *json, ei_x_buff *response)
{
    const char *entity_id = cJSON_GetObjectItem(json, "id")->valuestring;
    const char *owner_id = cJSON_GetObjectItem(json, "owner")->valuestring;
    printf("Adding entity %s for %s\n", entity_id, owner_id);
    allo_entity *ent = entity_create(entity_id);

    ent->owner_agent_id = strdup(owner_id);
    cJSON *components = cJSON_DetachItemFromObject(json, "components");
    ent->components = components;
    LIST_INSERT_HEAD(&state.entities, ent, pointers);

    ei_x_format_wo_ver(response, "{response, ~l, ok}", reqId);
}

static void simulate(long reqId, double dt, cJSON *jintents, ei_x_buff *response)
{
    int intent_count = cJSON_GetArraySize(jintents);
    allo_client_intent intents[intent_count];
    for(int i = 0; i < intent_count; i++)
    {
        cJSON *jintent = cJSON_GetArrayItem(jintents, i);
        intents[i].entity_id = cJSON_GetObjectItem(jintent, "entity_id")->valuestring;
        intents[i].zmovement = cJSON_GetObjectItem(jintent, "zmovement")->valuedouble;
        intents[i].xmovement = cJSON_GetObjectItem(jintent, "xmovement")->valuedouble;
        intents[i].yaw = cJSON_GetObjectItem(jintent, "yaw")->valuedouble;
        intents[i].pitch = cJSON_GetObjectItem(jintent, "pitch")->valuedouble;

        cJSON *poses = cJSON_GetObjectItem(jintent, "poses");
        intents[i].poses.head.matrix = cjson2m(cJSON_GetObjectItem(cJSON_GetObjectItem(poses, "head"), "matrix"));
        intents[i].poses.left_hand.matrix = cjson2m(cJSON_GetObjectItem(cJSON_GetObjectItem(poses, "hand/left"), "matrix"));
        intents[i].poses.right_hand.matrix = cjson2m(cJSON_GetObjectItem(cJSON_GetObjectItem(poses, "hand/right"), "matrix"));
    }
    allo_simulate(&state, dt, intents, intent_count);

    ei_x_format_wo_ver(response, "{response, ~l, ok}", reqId);
}

static void get_snapshot(long reqId, ei_x_buff *response)
{
    state.revision++;
    
    cJSON *jentities = cJSON_CreateObject();
    allo_entity *entity = NULL;
    LIST_FOREACH(entity, &state.entities, pointers)
    {
        cJSON *jentity = cjson_create_object("id", cJSON_CreateString(entity->id), NULL);
        cJSON_AddItemReferenceToObject(jentity, "components", entity->components);
        cJSON_AddItemToObject(jentities, entity->id, jentity);
    }

    cJSON *jresponse = cjson_create_object(
        "revision", cJSON_CreateNumber(state.revision),
        "entities", jentities,
        NULL
    );
    char *jsons = cJSON_PrintUnformatted(jresponse);
    
    // Respond with  {response, ResponseId, {ok, JSON}} where JSON is a binary, which is not something
    // we can express with ei_x_format.
    ei_x_encode_tuple_header(response, 3);
    ei_x_encode_atom(response, "response");
    ei_x_encode_long(response, reqId);
    ei_x_encode_tuple_header(response, 2);
    ei_x_encode_atom(response, "ok");
    ei_x_encode_binary(response, jsons, strlen(jsons));

    free(jsons);
    cJSON_Delete(jresponse);
}

static void get_owner_id(long reqId, const char *entity_id, ei_x_buff *response)
{
    allo_entity *entity = state_get_entity(&state, entity_id);
    if (!entity)
    {
        ei_x_format_wo_ver(response, "{response, ~l, {error, no_such_entity}}", reqId);
        return;
    }

    assert(entity->owner_agent_id);
    ei_x_encode_tuple_header(response, 3);
    ei_x_encode_atom(response, "response");
    ei_x_encode_long(response, reqId);
    ei_x_encode_tuple_header(response, 2);
    ei_x_encode_atom(response, "ok");
    ei_x_encode_binary(response, entity->owner_agent_id, strlen(entity->owner_agent_id));
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
        add_entity(reqId, json, &response);
    } else if(strcmp(command, "simulate") == 0) {
        double dt;
        assert(ei_decode_double(request, &request_index, &dt) == 0);
        cJSON *json = ei_decode_cjson_string(request, &request_index);
        simulate(reqId, dt, json, &response);
    } else if(strcmp(command, "get_snapshot") == 0) {
        get_snapshot(reqId, &response);
    } else if(strcmp(command, "get_owner_id") == 0) {
        assert(argsLen == 1);
        char *owner_id = ei_decode_elixir_string(request, &request_index);
        get_owner_id(reqId, owner_id, &response);
        free(owner_id);
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
