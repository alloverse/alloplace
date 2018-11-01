defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: AlloPlaceserv.TaskSupervisor},
      {AlloPlaceserv.Server, name: AlloPlaceserv.Serv},
      {AlloPlaceserv.PlaceStore, name: AlloPlaceserv.Store},
    ]

    opts = [strategy: :one_for_one, name: AlloPlaceserv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
