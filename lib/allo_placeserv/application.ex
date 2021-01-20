defmodule AlloPlaceserv.Application do
  @moduledoc """
  Main supervisor and stuff
  """
  use Application

  def start(_type, _args) do
    children = [
      %{
        id: Serv,
        start: {Server, :start_link, [[]]}
      },
    ]

    #:debugger.start()
    #:observer.start()

    opts = [strategy: :one_for_one, name: Supervisor]
    Supervisor.start_link(children, opts)
  end
end
