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
    GenServer.start_link(__MODULE__, {
    }, opts)
  end
  
  def handle_info({:new_client, client_id, mm_pid}, state) do
    :ok = AlloPlaceserv.PlaceStore.add_entity(AlloPlaceserv.Store, %Entity{
      id: client_id
    })
      #todo: store clients in a hashmap
  end
  #todo: handle lost client
  def handle_info({:lost_client, client_id}) do
    AlloPlaceserv.PlaceStore.remove_entity(AlloPlaceserv.Store, client_id)
    #todo: remove client from hashmap
  end
  
  #todo: handle sending world state with timer

  
  #todo: move this to mm
  defp parse_command(entityId, data) do
    case String.at(data, 0) do
      "w" -> :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, entityId, {:relative, [0,0,1]})
      "s" -> :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, entityId, {:relative, [0,0,-1]})
      "a" -> :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, entityId, {:relative, [0,0,-1]})
      "d" -> :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, entityId, {:relative, [0,0,1]})
    end
    :ok
  end
end
