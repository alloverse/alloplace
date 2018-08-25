defmodule AlloPlaceserv.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: AlloPlaceserv.TaskSupervisor},
      Supervisor.child_spec({Task, fn -> AlloPlaceserv.accept(16016) end}, restart: :permanent)
    ]

    opts = [strategy: :one_for_one, name: AlloPlaceserv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
