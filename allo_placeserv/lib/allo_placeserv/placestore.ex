defmodule StoreState do
  defstruct entities: []
end
defmodule Entity do
  @enforce_keys [:id]
  defstruct id: nil, position: [0,0,0]
end

defmodule AlloPlaceserv.PlaceStore do
  use GenServer
  require Logger
  
  def init(initial_state) do
    {:ok, initial_state}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %StoreState{
      
    }, opts)
  end
  
  ## Public methods
  def add_entity(server, ent) do
    GenServer.call(server, {:add_entity, ent})
  end
  def remove_entity(server, entity_id) do
    GenServer.cast(server, {:remove_entity, entity_id})
  end
  
  ## Server callbacks
  def handle_call({:add_entity, ent}, _from, state) do
    Logger.info "Adding entity #{ent.id}"
    {:reply, 
      :ok, 
      %{state | 
        entities: [ent | state.entities]
      }
    }
  end
  def handle_cast({:remove_entity, entity_id}, state) do
    Logger.info "Removing entity #{entity_id}"
    {:noreply,
      %{state |
      entities: List.keydelete(state.entities, entity_id, 2)
      }
    }
  end
end
