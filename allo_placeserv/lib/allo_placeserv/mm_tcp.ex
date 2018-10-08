defmodule AlloPlaceserv.MmTcp do
  def start(port, parent) do
    {:ok, pid} = Task.Supervisor.start_child(
      AlloPlaceserv.TaskSupervisor, 
      fn -> accept(port, parent) end
    )
    :ok
  end
  
  defp accept(port, parent) do
    {:ok, listen} = :gen_tcp.listen(port, [
      :binary, 
      packet: :line, 
      active: true, 
      reuseaddr: true
    ])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(parent, listen)
  end
  
  defp loop_acceptor(parent, listen) do
    {:ok, client} = :gen_tcp.accept(listen)
    connectionId = UUID.uuid1()
    {:ok, pid} = Task.Supervisor.start_child(
      AlloPlaceserv.TaskSupervisor, 
      fn -> serve(parent, client, connectionId) end
    )
    :ok = :gen_tcp.controlling_process(client, pid)
    parent ! {:new_client, connectionId, pid}
    loop_acceptor(socket)
  end

  defp serve(parent, client, connectionId) do
    # TODO: convert this to receive and active mode
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        :ok = parse_command(connectionId, data)
        serve(socket, connectionId)
      {:error, :closed} ->
        parent ! {:lost_client, connectionId}
        :close
    end
  end
end