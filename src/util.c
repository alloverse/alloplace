#include "util.h"
#include <assert.h>

cJSON *ei_decode_as_cjson(const char *buf, int *index)
{
    const char* s = buf + *index;
    int arity;
    double vf;
    char c = get8(s, index);
    cJSON *ret = NULL;

    switch (c) {
    case ERL_SMALL_INTEGER_EXT:
        ret = cJSON_CreateNumber(get8(s, index));
        printf("Decoding small integer %d at %d\n", ret->valueint, *index);
        break;
    case ERL_INTEGER_EXT:
        ret = cJSON_CreateNumber(get32be(s, index));
        printf("Decoding integer %d at %d\n", ret->valueint, *index);
        break;
    case ERL_FLOAT_EXT:
    case NEW_FLOAT_EXT:
        assert(ei_decode_double(buf, index, &vf) == 0);
        ret = cJSON_CreateNumber(vf);
        printf("Decoding double %f at %d\n", ret->valuedouble, *index);
        break;
    case ERL_ATOM_EXT:
    case ERL_ATOM_UTF8_EXT:
    case ERL_SMALL_ATOM_EXT:
    case ERL_SMALL_ATOM_UTF8_EXT: {
        char command[MAXATOMLEN];
	    assert(ei_decode_atom(buf, index, command) == 0);
        ret = cJSON_CreateString(command); 
        printf("Decoding atom %s at %d\n", ret->valuestring, *index);
        break; }
    case ERL_SMALL_TUPLE_EXT:
    case ERL_LARGE_TUPLE_EXT:
        arity = (c == ERL_SMALL_TUPLE_EXT) ? get8(s, index) : get32be(s, index);
        printf("Decoding tuple of lengh %d at %d\n", arity, *index);
        ret = cJSON_CreateArray();
        for(int i = 0; i < arity; i++) {
            printf("Decoding tuple child #%d at %d\n", i, *index);
            cJSON *child = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToArray(ret, child);
        }
        break;
    case ERL_NIL_EXT:
        ret = cJSON_CreateNull();
        printf("Decoding nil at %d\n", *index);
        break;
    case ERL_STRING_EXT: {
	    arity = get16be(s, index);
        char s[arity];
        assert(ei_decode_string(buf, index, s) == 0);
        printf("Decoding string %s at %d\n", s, *index);
        ret = cJSON_CreateString(s); 
        break; }
    case ERL_LIST_EXT:
        arity = get32be(s, index);
        ret = cJSON_CreateArray();
        printf("Decoding list of length %d at %d\n", arity, *index);
        for(int i = 0; i < arity; i++) {
            printf("Decoding list iem #%d at %d\n", i, *index);
            cJSON *child = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToArray(ret, child);
        }
        break;
    case ERL_MAP_EXT:
        arity = get32be(s, index);
        printf("Decoding map with %d children at %d\n", arity, *index);
        ret = cJSON_CreateObject();
        for(int i = 0; i < arity; i++) {
            cJSON *key = ei_decode_as_cjson(buf, index);
            assert(cJSON_IsString(key));
            printf("Decoding value for key %s at %d\n", key->valuestring, *index);
            cJSON *value = ei_decode_as_cjson(buf, index);
            cJSON_AddItemToObject(ret, key->valuestring, value);
        }
        break;
    }
    assert(ret != NULL && "unsupported type");
    return ret;
}