defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: AlloPlaceserv.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> AlloPlaceserv.Server.accept(16016) end}, restart: :permanent),
      {AlloPlaceserv.PlaceStore, name: AlloPlaceserv.Store},
    ]

    opts = [strategy: :one_for_one, name: AlloPlaceserv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
