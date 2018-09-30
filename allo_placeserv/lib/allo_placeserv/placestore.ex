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
end
