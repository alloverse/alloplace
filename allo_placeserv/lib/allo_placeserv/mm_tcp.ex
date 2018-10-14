defmodule AlloPlaceserv.MmTcp do
  require Logger
  
  def start(port, parent) do
    spawn_link(fn -> accept(port, parent) end)
    :ok
  end
  
  defp accept(port, parent) do
    {:ok, listen} = :gen_tcp.listen(port, [
      :binary, 
      packet: :line, 
      active: false, 
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
      fn ->
        serve(parent, client, connectionId) 
      end
    )
    :ok = :gen_tcp.controlling_process(client, pid)
    send pid, :become_active
    send parent, {:new_client, connectionId, pid}
    loop_acceptor(parent, listen)
  end

  defp serve(parent, client, connectionId) do
    receive do
      :become_active ->
        :inet.setopts(client, [active: true])
        serve(parent, client, connectionId)
        
      {:tcp, _socket, data} ->
        cmd = parse_command(connectionId, data)
        send parent, cmd
        serve(parent, client, connectionId)
      
      {:tcp_closed, _socket} ->
        send parent, {:lost_client, connectionId}
        :close
    end
  end
  
  defp parse_command(connectionId, data) do
    case String.at(data, 0) do
      "w" -> {:move_avatar, connectionId, {:relative, [0,0,1]}}
      "s" -> {:move_avatar, connectionId, {:relative, [0,0,-1]}}
      "a" -> {:move_avatar, connectionId, {:relative, [-1,0,0]}}
      "d" -> {:move_avatar, connectionId, {:relative, [1,0,0]}}
      # otherwise, crash
    end
  end
end