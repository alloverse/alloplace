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
  @derive {Jason.Encoder, only: [:id, :components, :owner] }
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
  def remove_entity(server, entity_id, mode) do
    GenServer.cast(server, {:remove_entity, entity_id, mode})
  end
  def remove_entities_owned_by(server, owner_id) do
    GenServer.cast(server, {:remove_entities_owned_by, owner_id})
  end

  @doc """
    Update a specific entity by replacing some of its components with new values
    `entity_id`: the entity to update
    `components`: Map of key string component name to value map of component
                attributes
    `removecomps`: List of component names to remove from the entity
  """
  def update_entity(server, entity_id, components, removecomps) do
    GenServer.call(server, {:update_entity, entity_id, components, removecomps})
  end

  def get_snapshot_deltas(server, old_revs) do
    # absolutely terrible hack to avoid ei giving us a bullshit string instead of a list
    GenServer.call(server, {:get_snapshot_deltas, [-65536]++old_revs})
  end

  def get_owner_id(server, entity_id) do
    GenServer.call(server, {:get_owner_id, entity_id})
  end

  def simulate(server, intents) do
    GenServer.call(server, {:simulate, intents})
  end

  def ping(this) do
    GenServer.call(this, {:ping, {}})
  end


end
