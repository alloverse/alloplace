#include <string.h>
#include <enet/enet.h>
#include <sys/fcntl.h>
#include <assert.h>

#include <allonet/allonet.h>
#include "erl_comm.h"
#include "util.h"
#include "allonet/src/util.h"
#include "allonet/src/delta.h"


////////// STATE MANAGEMENT AND HANDLER FUNCTIONS

allo_state state;
statehistory_t history;

static void add_entity(long reqId, cJSON *json, ei_x_buff *response)
{
    const char *entity_id = cJSON_GetObjectItem(json, "id")->valuestring;
    const char *owner_id = cJSON_GetObjectItem(json, "owner")->valuestring;
    printf("Adding entity %s for %s\n", entity_id, owner_id);
    allo_entity *ent = entity_create(entity_id);

    ent->owner_agent_id = allo_strdup(owner_id);
    cJSON *components = cJSON_DetachItemFromObject(json, "components");
    ent->components = components;
    LIST_INSERT_HEAD(&state.entities, ent, pointers);

    ei_x_format_wo_ver(response, "{response, ~l, ok}", reqId);
}

static void update_entity(long reqId, const char *entity_id, cJSON *comps, cJSON *rmcomps, ei_x_buff *response)
{
    allo_entity *entity = state_get_entity(&state, entity_id);
    cJSON *comp = NULL;
    for(cJSON *comp = comps->child; comp != NULL;)
    {
        cJSON *next = comp->next;
        cJSON_DeleteItemFromObject(entity->components, comp->string);
        cJSON_DetachItemViaPointer(comps, comp);
        cJSON_AddItemToObject(entity->components, comp->string, comp);
        comp = next;
    }
    
    cJSON_ArrayForEach(comp, rmcomps)
    {
        cJSON_DeleteItemFromObject(entity->components, comp->valuestring);
    }
    ei_x_format_wo_ver(response, "{response, ~l, ok}", reqId);
}

static void remove_entity_by_id(const char *entity_id, allo_removal_mode mode)
{
    allo_state_remove_entity(&state, entity_id, mode);
}

static void remove_entity_by_owner(const char *owner_id)
{
    allo_entity *entity = state.entities.lh_first;
    while(entity)
    {
        allo_entity *to_delete = entity;
        entity = entity->pointers.le_next;
        if (strcmp(to_delete->owner_agent_id, owner_id) == 0)
        {
            printf("Removing entity %s for %s\n", to_delete->id, to_delete->owner_agent_id);
            LIST_REMOVE(to_delete, pointers);
            entity_destroy(to_delete);
        }
    }
}

static void simulate(long reqId, double dt, cJSON *jintents, ei_x_buff *response)
{
    int intent_count = cJSON_GetArraySize(jintents);
    allo_client_intent *intents[intent_count];
    for(int i = 0; i < intent_count; i++)
    {
        cJSON *jintent = cJSON_GetArrayItem(jintents, i);
        intents[i] = allo_client_intent_parse_cjson(jintent);
    }
    allo_simulate(&state, dt, intents, intent_count);
    for(int i = 0; i < intent_count; i++)
    {
        allo_client_intent_free(intents[i]);
    }

    ei_x_format_wo_ver(response, "{response, ~l, ok}", reqId);
}

static void get_snapshot_deltas(long reqId, long long revs[], int rev_count, ei_x_buff *response)
{
    state.revision++;
    // roll over revision to 0 before it reaches biggest consecutive integer representable in json
    if(state.revision == 9007199254740990) { state.revision = 0; }
    
    cJSON *current = allo_state_to_json(&state);
    allo_delta_insert(&history, current);

    // {response, ResponseId, {ok, [JSON, ...]}}
    ei_x_encode_tuple_header(response, 3);
    ei_x_encode_atom(response, "response");
    ei_x_encode_long(response, reqId);
    ei_x_encode_tuple_header(response, 2);
    ei_x_encode_atom(response, "ok");
    ei_x_encode_list_header(response, rev_count);

    for(int i = 0; i < rev_count; i++)
    {
        scoped char *jsons = allo_delta_compute(&history, revs[i]);
        ei_x_encode_binary(response, jsons, strlen(jsons));
    }
    if(rev_count > 0)
    {
        ei_x_encode_empty_list(response);
    }
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
    if(strcmp(command, "ping") == 0)
    {
        ei_x_format_wo_ver(&response, "{response, ~l, statepong}", reqId);
    }
    else if(strcmp(command, "add_entity") == 0)
    {
        scopedj cJSON *json = ei_decode_cjson_string(request, &request_index);
        add_entity(reqId, json, &response);
    }
    else if(strcmp(command, "update_entity") == 0)
    {
        scoped char *entity_id = ei_decode_elixir_string(request, &request_index);
        scopedj cJSON *cjson = ei_decode_cjson_string(request, &request_index);
        scopedj cJSON *rmjson = ei_decode_cjson_string(request, &request_index);

        update_entity(reqId, entity_id, cjson, rmjson, &response);
    }
    else if(strcmp(command, "remove_entity") == 0)
    {
        scoped char *entity_id = ei_decode_elixir_string(request, &request_index);
        scoped char *modes = ei_decode_elixir_string(request, &request_index);
        allo_removal_mode mode = AlloRemovalCascade;
        if(modes && strcmp(modes, "reparent") == 0)
        {
            mode == AlloRemovalReparent;
        }

        remove_entity_by_id(entity_id, mode);
    }
    else if(strcmp(command, "remove_entities_owned_by") == 0)
    {
        scoped char *owner_id = ei_decode_elixir_string(request, &request_index);
        remove_entity_by_owner(owner_id);
    }
    else if(strcmp(command, "simulate") == 0)
    {
        double dt;
        assert(ei_decode_double(request, &request_index, &dt) == 0);
        scopedj cJSON *json = ei_decode_cjson_string(request, &request_index);
        simulate(reqId, dt, json, &response);
    }
    else if(strcmp(command, "get_snapshot_deltas") == 0)
    {
        int rev_count;
        assert(ei_decode_list_header(request, &request_index, &rev_count) == 0);
        long long old_revs[rev_count];
        // skip bullshit hack (list must contain integer >255 so we don't get a byte buffer)
        assert(ei_decode_longlong(request, &request_index, old_revs) == 0);
        rev_count--;
        for(int i = 0; i < rev_count+1; i++) {
            int type, size;
            assert(ei_get_type(request, &request_index, &type, &size) == 0);
            switch(type) {
                case ERL_SMALL_INTEGER_EXT:
                case ERL_INTEGER_EXT:
                    assert(ei_decode_longlong(request, &request_index, old_revs+i) == 0);
                    break;
                case ERL_LIST_EXT:
                case ERL_NIL_EXT:
                    assert(ei_decode_list_header(request, &request_index, &size) == 0);
                    assert(i == rev_count); //. list should end...
                    assert(size == 0); // ... with an empty tail
                    break;
                default:
                    assert(0 && "improper list");
            }
        }

        get_snapshot_deltas(reqId, old_revs, rev_count, &response);
    }
    else if(strcmp(command, "get_owner_id") == 0)
    {
        assert(argsLen == 1);
        scoped char *owner_id = ei_decode_elixir_string(request, &request_index);
        get_owner_id(reqId, owner_id, &response);
    }
    else
    {
        printf("statedaemon: Unknown command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"no such command\"}}", reqId);
    }
    if(response.index == 0 && reqId != -1)
    {
        printf("statedaemon: Missing response to command %s\n", command);
        ei_x_format_wo_ver(&response, "{response, ~l, {error, \"missing response\"}}", reqId);        
    }

    if(reqId != -1) {
        write_cmd((uint8_t*)response.buff, response.index);
    }
}

int main()
{
    if(!allo_initialize(false))
    {
        fprintf(stderr, "Unable to initialize allostate");
        return -1;
    }

    ei_init();

    if(fcntl(erlin, F_SETFL, O_NONBLOCK) != 0)
    {
        perror("failed to set erlin as non-blocking");
        return -4;
    }
    
    printf("allostateport open as %d\n", getpid());
    
    while (1)
    {
        ENetSocketSet set;
        ENET_SOCKETSET_EMPTY(set);
        ENET_SOCKETSET_ADD(set, erlin);
        
        int selectr = enet_socketset_select(erlin, &set, NULL, 100);
        if(selectr < 0)
        {
            if(errno == EINTR) {
                // debugger attached or something, just retry
                continue;
            }
            perror("select failed, terminating");
            return -3;
        }
        else if(ENET_SOCKETSET_CHECK(set, erlin))
        {
            handle_erl();
        }
    }
    return 0;
}
