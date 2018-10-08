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
  
  def handle_info({:new_client, client_id, _mm_pid}, state) do
    :ok = AlloPlaceserv.PlaceStore.add_entity(AlloPlaceserv.Store, %Entity{
      id: client_id
    })
      #todo: store clients in a hashmap
    {:noreply, state}
  end
  
  def handle_info({:lost_client, client_id}, state) do
    AlloPlaceserv.PlaceStore.remove_entity(AlloPlaceserv.Store, client_id)
    #todo: remove client from hashmap
    {:noreply, state}
  end
  
  def handle_info({:move_avatar, connectionId, movement}, state) do
    :ok = AlloPlaceserv.PlaceStore.move_entity(AlloPlaceserv.Store, connectionId, movement)
    {:noreply, state}
  end
  
  #todo: handle sending world state with timer
end
