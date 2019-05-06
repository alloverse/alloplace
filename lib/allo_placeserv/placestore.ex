defmodule StoreState do
  @derive Jason.Encoder
  defstruct entities: %{},
  revision: 0
end

# Todo: schema for component that generates these in elixir and c and c#...

defmodule AlloVector do
  @derive Jason.Encoder
  defstruct x: 0.0,
    y: 0.0,
    z: 0.0
end

defmodule TransformComponent do
  @derive Jason.Encoder
  defstruct position: %AlloVector{},
    rotation: %AlloVector{}
end

defmodule Entity do
  @enforce_keys [:id]
  @derive Jason.Encoder
  defstruct id: "",
    components: %{
      transform: %TransformComponent{}
    }
end

defmodule PlaceStore do
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

  @doc """
    Update a specific entity by replacing some of its components with new values
    `entity_id`: the entity to update
    `components`: Map of key string component name to value map of component
                attributes
  """
  def update_entity(server, entity_id, components) do
    GenServer.call(server, {:update_entity, entity_id, components})
  end
  @doc """
    Update a specific entity by executing given fun on a named component,
    mapping its contents to new values
  """
  def update_entity(server, entity_id, component_name, fun) do
    GenServer.call(server, {:update_entity, entity_id, component_name, fun})
  end
  def get_snapshot(server) do
    GenServer.call(server, {:get_snapshot})
  end

  ## Server callbacks
  def handle_call({:add_entity, ent}, _from, state) do
    Logger.info "Adding entity #{ent.id}"
    { :reply,
      :ok,
      %{state |
        entities: Map.put(state.entities, ent.id, ent)
      }
    }
  end

  def handle_call({:update_entity, entity_id, components}, _from, state) do
    { :reply,
      :ok,
      %{state|
        entities: Map.update!(state.entities, entity_id, fn(entity) -> %{entity|
          components: Map.merge(entity.components, components, fn _k, _v1, v2 ->
            v2
          end)
        } end )
      }
    }
  end
  def handle_call({:update_entity, entity_id, component_name, fun}, _from, state) do
    { :reply,
      :ok,
      %{state|
        entities: Map.update!(state.entities, entity_id, fn(entity) -> %{entity|
          components: Map.update!(entity.components, component_name, fn component ->
            fun.(component)
          end)
        } end )
      }
    }
  end

  def handle_call({:get_snapshot}, _from, state) do
    { :reply,
      {:ok, state},
      %{state|
        revision: state.revision + 1
      }
    }
  end

  def handle_cast({:remove_entity, entity_id}, state) do
    new_entities = Map.delete(state.entities, entity_id)
    Logger.info "Removing entity #{entity_id}, now #{length(Map.keys(new_entities))}"
    { :noreply,
      %{state |
        entities: new_entities
      }
    }
  end

  ## Internals

end
