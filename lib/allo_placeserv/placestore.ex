defmodule StoreState do
  @derive Jason.Encoder
  defstruct entities: %{},
  revision: 0
end

# Todo: schema for component that generates these in elixir and c and c#...

defmodule TransformComponent do
  defstruct matrix: Graphmath.Mat44.identity()
end
defimpl Jason.Encoder, for: TransformComponent do
  def encode(struct, opts) do
    Jason.Encode.map(%{
      matrix: Tuple.to_list(
        struct.matrix
      )
    }, opts)
  end
end

defmodule RelationshipsComponent do
  @derive Jason.Encoder
  defstruct parent: nil
end

defmodule IntentComponent do
  @derive Jason.Encoder
  defstruct actuate_pose: nil
end

defmodule LiveMediaComponent do
  @derive Jason.Encoder
  defstruct type: "audio",
    track_id: 0,
    sample_rate: 48000,
    channel_count: 1,
    format: "opus"
end

defmodule Entity do
  @enforce_keys [:id]
  @derive {Jason.Encoder, only: [:id, :components] }
  defstruct id: "",
    components: %{
      transform: %TransformComponent{},
      relationships: %RelationshipsComponent{},
      intent: %IntentComponent{},
      live_media: %LiveMediaComponent{}
    },
    owner: "" # client_id
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
  def remove_entities_owned_by(server, owner_id) do
    GenServer.cast(server, {:remove_entities_owned_by, owner_id})
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

  def get_snapshot(server) do
    GenServer.call(server, {:get_snapshot})
  end

  def get_owner_id(server, entity_id) do
    GenServer.call(server, {:get_owner_id, entity_id})
  end

  def simulate(server, dt, intents) do
    GenServer.call(server, {:simulate, dt, intents})
  end

  def ping(this) do
    GenServer.call(this, {:ping, {}})
  end

  ## Server callbacks
  def handle_cast({:remove_entity, entity_id}, state) do
    new_entities = Map.delete(state.entities, entity_id)
    Logger.info "Removing entity #{entity_id}, now #{length(Map.keys(new_entities))}"
    { :noreply,
      %{state |
        entities: new_entities
      }
    }
  end
  def handle_cast({:remove_entities_owned_by, owner_id}, state) do
    new_entities = Enum.reject(state.entities, fn {_eid, ent} -> ent.owner == owner_id end) |> Enum.into(%{})
    Logger.info "Removing all entities for owner #{owner_id}, now #{length(Map.keys(new_entities))}"
    { :noreply,
      %{state |
        entities: new_entities
      }
    }
  end

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

  def handle_call({:find_entity, fun}, _from, state) do
    { :reply,
      case Enum.find(state.entities, nil, fun) do
        nil -> {:error, :notfound}
        {_key, ent} -> {:ok, ent}
      end,
      state
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

  def handle_call({:get_owner_id, entity_id}, _from, state) do
    {:reply,
      {:ok,
        state.entities[entity_id].owner
      },
      state
    }
  end

  def handle_call({:simulate, dt, intents}, _from, state) do


    {:reply,
      :ok,
      state
    }
  end



  ## Internals

end
