defmodule StoreState do
  defstruct entities: %{}
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
  def move_entity(server, entity_id, movement_cmd) do
    GenServer.call(server, {:move_entity, entity_id, movement_cmd})
  end
  
  ## Server callbacks
  def handle_call({:add_entity, ent}, _from, state) do
    Logger.info "Adding entity #{ent.id}"
    {:reply, 
      :ok, 
      %{state | 
        entities: Map.put(state.entities, ent.id, ent)
      }
    }
  end
  
  def handle_call({:move_entity, entity_id, {type, newpos}}, _from, state)
  when length(newpos) == 3 do
    {:ok, entity} = Map.fetch(state.entities, entity_id)
    Logger.info "Moving entity #{entity_id} with #{type}"
    {:reply,
      :ok,
      %{state|
        entities: Map.put(state.entities, entity_id, %{entity|
          position: case type do
            :absolute -> newpos
            :relative -> 
              Enum.map(Enum.zip(entity.position, newpos), fn {a,b} -> a+b end)
          end
        })}
    }
  end
  
  def handle_cast({:remove_entity, entity_id}, state) do
    Logger.info "Removing entity #{entity_id}, now #{length(Map.keys(state.entities))}"
    {:noreply,
      %{state |
        entities: Map.delete(state.entities, entity_id)
      }
    }
  end
  
  ## Internals
  
end
