defmodule AlloPlaceserv.Server do
  @moduledoc """
  I think this class starts out handling network and manipulating the world state, while
  placestore actually holds it.
  """
  
  require Logger

  @doc """
  Starts accepting connections on the given `port`.
  """
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    entityId = UUID.uuid1()
    :ok = AlloPlaceserv.PlaceStore.add_entity(AlloPlaceserv.Store, %Entity{
      id: entityId
    })
    {:ok, pid} = Task.Supervisor.start_child(AlloPlaceserv.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    socket
    |> read_line()
    |> write_line(socket)

    serve(socket)
  end

  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end

  defp write_line(line, socket) do
    :gen_tcp.send(socket, line)
  end
end
