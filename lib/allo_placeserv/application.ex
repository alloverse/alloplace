defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    # If we're not running on a properly provisioned server, make sure we have a dummy
    # storage folder available.
    File.mkdir("storage")

    # Make sure we start with an empty state, so we don't start from stale state..
    # In the future, we can use the stored information to reconnect clients and continue
    # from this stale state, but we're not there yet.
    # StateProc isn't alive yet so we can't use PlaceStore.reset(StateProc)
    File.rm("storage/state.json")

    # Alright, boot it up! The order here is important.
    children = [
      {PlaceStoreDaemon, [name: StateProc]},
      {StateBackupper, [name: BackupProc]},
      {Server, [name: ServProc]},
      {NetDaemon, [name: NetProc, delegate: ServProc, port: 31337]},
    ]

    #:debugger.start()
    #:observer.start()

    opts = [strategy: :one_for_one, name: Supervisor]
    Supervisor.start_link(children, opts)
  end
end
