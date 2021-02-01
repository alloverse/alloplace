defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    # If we're not running on a properly provisioned server, make sure we have dummy
    # tmp and storage folders available.
    File.mkdir("storage")
    File.mkdir("tmp")

    #:debugger.start()
    #:observer.start()

    # Setup a root supervisor that just makes sure we serve basically forever, even if
    # everything keeps crashing
    Supervisor.start_link([
      AlloPlaceserv.MainSupervisor
    ], [
      strategy: :one_for_one,
      max_restarts: 100,
      max_seconds: 10,
      name: RestartTheWorldSupervisor
    ])
  end
end

defmodule AlloPlaceserv.MainSupervisor do
  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting main supervisor from scratch")
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

    Supervisor.init(children, [
      strategy: :one_for_one,
    ])
  end
end
