defmodule StoreState do
  @derive Jason.Encoder
  defstruct entities: %{},
  revision: 0
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

  def simulate(server, intents, server_time) do
    GenServer.call(server, {:simulate, intents, server_time})
  end

  def ping(this) do
    GenServer.call(this, {:ping, {}})
  end


end
