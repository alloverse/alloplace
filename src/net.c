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
    
    scoped_comp ETERM *command = erl_element(1, tuplep);
    scoped_comp ETERM *reqId = erl_element(2, tuplep);
    scoped_comp ETERM *args = erl_element(3, tuplep);
    
    if (strcmp(ERL_ATOM_PTR(command), "disconnect") == 0) {
        scoped_term ETERM* e_client_ptr = erl_element(1, args);
        void *client_ptr = (void*)ERL_LL_UVALUE(e_client_ptr);
        alloserver_client *client;
        LIST_FOREACH(client, &serv->clients, pointers)
        {
            if(client == client_ptr) {
                serv->disconnect(serv, client);
                scoped_comp ETERM *msg = erl_format("{response, ~w, ok}", reqId);
                write_term(msg);
                return;
            }
        }
        scoped_comp ETERM *msg = erl_format("{response, ~w, {error, \"no such client\"}}", reqId);
        write_term(msg);
        return;
    } else if (strcmp(ERL_ATOM_PTR(command), "stop") == 0) {
        serv->stop(serv, 1000);
        scoped_comp ETERM *msg = erl_format("{response, ~w, ok}", reqId);
        write_term(msg);
        return;
    } else if (strcmp(ERL_ATOM_PTR(command), "send") == 0) {
        scoped_term ETERM* payload = erl_element(3, args);
        scoped_term ETERM* channel = erl_element(2, args);
        scoped_term ETERM* e_client_ptr = erl_element(1, args);
        void *client_ptr = (void*)ERL_LL_UVALUE(e_client_ptr);
        alloserver_client *client;
        LIST_FOREACH(client, &serv->clients, pointers)
        {
            
            if(client == client_ptr) {
                serv->send(
                    serv,
                    client,
                    ERL_INT_VALUE(channel),
                    (const uint8_t*)ERL_BIN_PTR(payload),
                    ERL_BIN_SIZE(payload)
                );
                scoped_comp ETERM *msg = erl_format("{response, ~w, ok}", reqId);
                write_term(msg);
                return;
            }
        }
        scoped_comp ETERM *msg = erl_format("{response, ~w, {error, \"no such client\"}}", reqId);
        write_term(msg);
        return;
    } else if(strcmp(ERL_ATOM_PTR(command), "ping") == 0) {
        scoped_comp ETERM *msg = erl_format("{response, ~w, netpong}", reqId);
        write_term(msg);
        return;
    }
    
    scoped_comp ETERM *msg = erl_format("{response, ~w, {error, \"no such command\"}}", reqId);
    write_term(msg);
    return;
}

void clients_changed(alloserver *serv, alloserver_client *added, alloserver_client *removed)
{
    if(added) {
        scoped_comp ETERM *msg = erl_format("{client_connected, ~w}", erl_mk_ulonglong((unsigned long long)added));
        write_term(msg);
    } else {
        scoped_comp ETERM *msg = erl_format("{client_disconnected, ~w}", erl_mk_ulonglong((unsigned long long)removed));
        write_term(msg);
    }
}

void client_sent(alloserver *serv, alloserver_client *client, allochannel channel, const uint8_t *data, size_t data_length)
{
    scoped_comp ETERM *msg = erl_format(
        "{client_sent, ~w, ~i, ~w}",
        erl_mk_ulonglong((unsigned long long)client),
        channel,
        erl_mk_binary((const char*)data, data_length)
    );
    write_term(msg);
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
    serv->raw_indata_callback = client_sent;
    LIST_INIT(&serv->state.entities);

    erl_init(NULL, 0);
    
    int allosocket = allo_socket_for_select(serv);
    if(fcntl(erlin, F_SETFL, O_NONBLOCK) != 0) {
        perror("failed to set erlin as non-blocking");
        return -4;
    }
    
    printf("allonetport open as %d\n", getpid());
    
    while (1) {
        ENetSocketSet set;
        ENET_SOCKETSET_EMPTY(set);
        ENET_SOCKETSET_ADD(set, allosocket);
        ENET_SOCKETSET_ADD(set, erlin);
        
        int selectr = enet_socketset_select(MAX(allosocket, erlin), &set, NULL, 100);
        if(selectr < 0) {
            perror("select failed, terminating");
            return -3;
        } else if(ENET_SOCKETSET_CHECK(set, erlin)) {
            handle_erl();
        } { // else if(ENET_SOCKETSET_CHECK(set, allosocket)) {
            // just... always poll allo every 100ms, regardless
            handle_allo();
        }
    }

    return 0;
}
