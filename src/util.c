#include "util.h"
#include <assert.h>

cJSON *ei_decode_cjson_string(const char *buf, int *index)
{
    int type, size;
    assert(ei_get_type(buf, index, &type, &size) == 0);
    assert(type == ERL_BINARY_EXT);
    char s[size+1];
    long actualLength;
    assert(ei_decode_binary(buf, index, s, &actualLength) == 0);
    assert(actualLength == size);
    s[actualLength] = '\0';
    cJSON *json = cJSON_Parse(s);
    assert(json != NULL);
    return json;
}

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


/// NOTE: This is broken, not sure how. Giving up on it for now but keeping it because
/// I feel like it will become very useful in the future (as a reference, if nothing else)
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
        printf("About to decode atom. Type is %d, length is %d+%d. at %d\n", c, s[0], s[1], *index);
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