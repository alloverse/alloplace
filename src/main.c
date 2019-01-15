#include <string.h>
#include <erl_interface.h>
#include <allonet/allonet.h>
#include "erl_comm.h"

int foo(int a) { return a*2; }
int bar(int a) { return a*3; }

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

  ETERM *tuplep, *intp;
  ETERM *fnp, *argp;
  int res;
  uint8_t buf[100];

  erl_init(NULL, 0);

  while (read_cmd(buf) > 0) {
    tuplep = erl_decode(buf);
    fnp = erl_element(1, tuplep);
    argp = erl_element(2, tuplep);
    
    if (strncmp(ERL_ATOM_PTR(fnp), "foo", 3) == 0) {
      res = foo(ERL_INT_VALUE(argp));
    } else if (strncmp(ERL_ATOM_PTR(fnp), "bar", 3) == 0) {
      res = bar(ERL_INT_VALUE(argp));
    }

    intp = erl_mk_int(res);
    erl_encode(intp, buf);
    write_cmd(buf, erl_term_len(intp));

    erl_free_compound(tuplep);
    erl_free_term(fnp);
    erl_free_term(argp);
    erl_free_term(intp);
  }

  return 0;
}
