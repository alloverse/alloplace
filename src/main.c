#include <string.h>
#include <erl_interface.h>
#include <allonet/allonet.h>
#include "erl_comm.h"
#include <enet/enet.h>
#include <sys/fcntl.h>

 #define MAX(a,b) \
   ({ __typeof__ (a) _a = (a); \
       __typeof__ (b) _b = (b); \
     _a > _b ? _a : _b; })

void erl_free_term_handle(ETERM **term) { erl_free_term(*term); }
void erl_free_compound_handle(ETERM **term) { erl_free_compound(*term); }
#define scoped_term __attribute__ ((__cleanup__(erl_free_term_handle)))
#define scoped_comp __attribute__ ((__cleanup__(erl_free_compound_handle)))
void free_handle(uint8_t **handle) { free(*handle); }
#define scoped __attribute__ ((__cleanup__(free_handle)))

void write_term(ETERM *term)
{
    scoped uint8_t *outbuf = malloc(erl_term_len(term));
    erl_encode(term, outbuf);
    write_cmd(outbuf, erl_term_len(term));
}

int foo(int a) { return a*2; }
int bar(int a) { return a*3; }

alloserver *serv;

void handle_allo()
{
    while(serv->interbeat(serv, 1)) {}
}

void handle_erl()
{
    scoped uint8_t *buf = read_cmd();
    if(!buf)
        return;
    scoped_comp ETERM *tuplep = erl_decode(buf);
    
    scoped_term ETERM *fnp = erl_element(1, tuplep);
    scoped_term ETERM *argp = erl_element(2, tuplep);
    int res = 0;
    if (strncmp(ERL_ATOM_PTR(fnp), "foo", 3) == 0) {
      res = foo(ERL_INT_VALUE(argp));
    } else if (strncmp(ERL_ATOM_PTR(fnp), "bar", 3) == 0) {
      res = bar(ERL_INT_VALUE(argp));
    } else {
        return;
    }
    
    scoped_term ETERM *intp = erl_mk_int(res);
    scoped uint8_t *outbuf = malloc(erl_term_len(intp));
    erl_encode(intp, outbuf);
    write_cmd(outbuf, erl_term_len(intp));
}

void clients_changed(alloserver *serv, alloserver_client *added, alloserver_client *removed)
{
    if(added) {
        scoped_comp ETERM *msg = erl_format("{client_connected, ~i}", added);
        write_term(msg);
    } else {
        scoped_comp ETERM *msg = erl_format("{client_disconnected, ~i}", removed);
        write_term(msg);
    }
}


int main()
{
    if(!allo_initialize(false)) {
        fprintf(stderr, "Unable to initialize allonet");
        return -1;
    }

    serv = allo_listen();
    if(!serv) {
        fprintf(stderr, "Unable to create allonet server. Is port in use?\n");
        perror("errno");
        return -2;
    }
    serv->clients_callback = clients_changed;
    LIST_INIT(&serv->state.entities);

    erl_init(NULL, 0);
    
    int allosocket = allo_socket_for_select(serv);
    if(fcntl(erlin, F_SETFL, O_NONBLOCK) != 0) {
        perror("failed to set erlin as non-blocking");
        return -4;
    }
    
    printf("allonetport open\n");
    
    while (1) {
        ENetSocketSet set;
        ENET_SOCKETSET_EMPTY(set);
        ENET_SOCKETSET_ADD(set, allosocket);
        ENET_SOCKETSET_ADD(set, erlin);
        
        int selectr = enet_socketset_select(MAX(allosocket, erlin), &set, NULL, 1000);
        if(selectr < 0) {
            perror("select failed, terminating");
            return -3;
        } else if(ENET_SOCKETSET_CHECK(set, allosocket)) {
            handle_allo();
        } else if(ENET_SOCKETSET_CHECK(set, erlin)) {
            handle_erl();
        }
    }

    return 0;
}
