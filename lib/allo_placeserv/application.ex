defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    children = [
      {PlaceStoreDaemon, [name: StateProc]},
      {Server, [name: ServProc]},
      {NetDaemon, [name: NetProc, delegate: ServProc, port: 31337]},
    ]

    #:debugger.start()
    #:observer.start()

    opts = [strategy: :one_for_one, name: Supervisor]
    Supervisor.start_link(children, opts)
  end
end
