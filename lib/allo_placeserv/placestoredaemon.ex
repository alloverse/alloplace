defmodule PlaceStore do
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

  def save_state(this) do
    GenServer.call(this, {:save_state, {}})
  end

end


defmodule PlaceStoreDaemon do
  use GenServer
  require Logger

  ### Public API

  def start_link(opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, {}, opts)
    :statepong = PlaceStore.ping(pid)
    :ok = PlaceEntity.init(pid)
    {:ok, pid}
  end

  def init(_) do
    {:ok, Daemon.setup("priv/AlloStatePort")}
  end

  # ... + the public methods in PlaceStore

  ### Internals

  def handle_call(:stop, _from, state) do
    :ok = Daemon.stop(state)
    { :reply,
      :ok,
      state
    }
  end

  def handle_call(ccall, from, state) do
    cmd = elem(ccall, 0)
    args = case ccall do
      {:add_entity, entity} -> with {:ok, json} <- Jason.encode(entity), do: {json}
      {:update_entity, eid, comps, rmcomps} -> with(
        {:ok, cjson} <- Jason.encode(comps),
        {:ok, rmjson} <- Jason.encode(rmcomps),
        do: {eid, cjson, rmjson})
      {:simulate, intents, server_time} -> with {:ok, json} <- Poison.encode(intents), do: {json, server_time}
      _ -> Tuple.delete_at(ccall, 0)
    end
    {:ok, dstate} = Daemon.call_to_c(cmd, args, from, state)
    { :noreply,
      dstate
    }
  end

  def handle_cast(ccall, state) do
    cmd = elem(ccall, 0)
    args = Tuple.delete_at(ccall, 0)
    {:ok, dstate} = Daemon.call_to_c(cmd, args, state)
    { :noreply,
      dstate
    }
  end

  def handle_info({_from, {:data, data}}, state) do
    {:ok, dstate} = Daemon.handle_call_from_c(data, state)
    {
      :noreply,
      dstate
    }
  end

  # why is :EXIT callled but not this?
  def handle_info({_port, {:exit_status, status}}, state) do
    raise("AlloStatePort died unexpectedly: #{status}")
    {
      :noreply,
      state
    }
  end

  def handle_info({:EXIT, _port, mode}, state) do
    raise("AlloStatePort died unexpectedly: #{mode}")
    {
      :noreply,
      state
    }
  end

end
