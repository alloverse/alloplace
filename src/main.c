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


int foo(int a) { return a*2; }
int bar(int a) { return a*3; }

void handle_allo()
{

}

void handle_erl()
{
    ETERM *tuplep, *intp;
    ETERM *fnp, *argp;
    int res;
    uint8_t buf[100];
    
    // todo: read
    
    // todo: check for false positive on select
    
    tuplep = erl_decode(buf);
    fnp = erl_element(1, tuplep);
    argp = erl_element(2, tuplep);

    if (strncmp(ERL_ATOM_PTR(fnp), "foo", 3) == 0) {
      res = foo(ERL_INT_VALUE(argp));
    } else if (strncmp(ERL_ATOM_PTR(fnp), "bar", 3) == 0) {
      res = bar(ERL_INT_VALUE(argp));
    } else {
        return;
    }

    intp = erl_mk_int(res);
    erl_encode(intp, buf);
    write_cmd(buf, erl_term_len(intp));

    erl_free_compound(tuplep);
    erl_free_term(fnp);
    erl_free_term(argp);
    erl_free_term(intp);
}

int main()
{
    if(!allo_initialize(false)) {
        fprintf(stderr, "Unable to initialize allonet");
        return -1;
    }

    alloserver *serv = allo_listen();
    if(!serv) {
        fprintf(stderr, "Unable to create allonet server. Is port in use?\n");
        perror("errno");
        return -2;
    }
    //serv->clients_callback = clients_changed;
    LIST_INIT(&serv->state.entities);

    erl_init(NULL, 0);
    
    int allosocket = allo_socket_for_select(serv);
    if(fcntl(erlin, F_SETFL, O_NONBLOCK) != 0) {
        perror("failed to set erlin as non-blocking");
        return -4;
    }
    
    while (1) {
        ENetSocketSet set;
        ENET_SOCKETSET_EMPTY(set);
        ENET_SOCKETSET_ADD(set, allosocket);
        ENET_SOCKETSET_ADD(set, erlin);

        int selectr = enet_socketset_select(MAX(allosocket, erlin), &set, NULL, 1);
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
