defmodule ServerState do
  defstruct clients: %{} # client_id to ClientRef
end
defmodule ClientRef do
  @enforce_keys [:pid, :monitor, :id]
  defstruct pid: nil, monitor: nil, id: nil
end

defmodule AlloPlaceserv.Server do
  @moduledoc """
  I think this class starts out handling network and manipulating the world state, while
  placestore actually holds it.
  """
  use GenServer
  require Logger

  def init(initial_state) do
    AlloPlaceserv.MmTcp.start(16016, self())
    {:ok, initial_state}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %ServerState{
      
    }, opts)
  end
  
  def handle_info({:new_client, client_id, mm_pid}, state) do
    Logger.info("Client connected: #{client_id}")
    {:ok, state} = add_client(client_id, mm_pid, state)
    {:noreply, state}
  end
  
  def handle_info({:lost_client, client_id}, state) do
    Logger.info("Client disconnected: #{client_id}")
    {:ok, state} = remove_client(client_id, state)
    {:noreply, state}
  end
  def handle_info({:DOWN, _monitor_ref, :process, _mm_pid, reason}, state) when reason == :normal do
    # handled by lost_client. this message is only sent because the monitor isn't removed in time.
    {:noreply, state}
  end
  def handle_info({:DOWN, _monitor_ref, :process, mm_pid, reason}, state) do
    {_client_id, client} = Enum.find(state.clients, fn({_key, client}) -> client.pid == mm_pid end)
    Logger.info("Client crashed: #{client.id} reason: #{inspect(reason)}")
    {:ok, state} = remove_client(client.id, state)
    {:noreply, state}
  end
  
  def handle_info({:move_avatar, connectionId, movement}, state) do
    :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, connectionId, movement)
    {:noreply, state}
  end
  
  #todo: handle sending world state with timer
  
  
  ### Privates
  defp add_client(client_id, mm_pid, state) do
    monitorref = Process.monitor(mm_pid)
    :ok = AlloPlaceserv.PlaceStore.add_entity(AlloPlaceserv.Store, %Entity{
      id: client_id
    })
    {
      :ok,
      %ServerState{state|
        clients: Map.put(state.clients, client_id, %ClientRef{
          pid: mm_pid, monitor: monitorref,id: client_id
        })
      }
    }
  end
  defp remove_client(client_id, state) do
    {:ok, clientref} = Map.fetch(state.clients, client_id)
    Process.demonitor(clientref.monitor)
    :ok = AlloPlaceserv.PlaceStore.remove_entity(AlloPlaceserv.Store, client_id)
    {
      :ok,
      %ServerState{state|
        clients: Map.delete(state.clients, client_id)
      }
    }
  end
end
