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
      {AlloPlaceserv.Server, name: AlloProcs.Serv},
      {AlloPlaceserv.PlaceStore, name: AlloProcs.Store},
    ]

    opts = [strategy: :one_for_one, name: AlloPlaceserv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
