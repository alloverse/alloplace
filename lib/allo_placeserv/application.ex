defmodule AlloProcs do
end

defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: AlloProcs.TaskSupervisor},
      {PlaceStoreDaemon, name: AlloProcs.Store},
      {Server, name: AlloProcs.Serv},
    ]

    opts = [strategy: :one_for_one, name: Supervisor]
    Supervisor.start_link(children, opts)
  end
end
