defmodule ServerState do
  defstruct clients: %{}, # from client_id to ClientRef
    push_state_timer: nil,
    name: "Unnamed place",
    next_free_track: 1,
    start_time: 0.0,
    store: nil,
    mmallo: nil

  @type t :: %ServerState{
    clients: %{required(String.t()) => ClientRef.t()},
    push_state_timer: reference(),
    name: String.t(),
    next_free_track: Integer.t()
  }
end

defmodule ClientRef do
  @enforce_keys [:id]
  defstruct id: nil,
    identity: %ClientIdentity{},
    avatar_id: nil,
    intent: %ClientIntent{}
  @type t :: %ClientRef{id: String.t(), avatar_id: String.t(), intent: ClientIntent.t()}
end


defmodule Server do
  @moduledoc """
  I think this class starts out handling network and manipulating the world state, while
  placestore actually holds it.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    name = System.get_env("ALLOPLACE_NAME", "Unnamed place")
    GenServer.start_link(__MODULE__, %ServerState{
      name: name
    }, opts)
  end

  def init(initial_state) do
    Logger.info("Starting Alloverse Place server '#{initial_state.name}'")

    # update state and send world state @ 20hz
    tref = Process.send_after(self(), :timer, div(1000, 20))

    :ok = PlaceEntity.init(StateProc)

    { :ok,
      %ServerState{initial_state|
        push_state_timer: tref,
        mmallo: NetProc,
        store: StateProc,
        start_time: System.monotonic_time
      }
    }
  end

  ### GenServer
  def handle_info({:client_intent, client_id, intent_packet}, state) do
    handle_client_intent(client_id, intent_packet, state)
  end
  def handle_info(:timer, state) do
    handle_timer(state)
  end

  def handle_info({:client_interaction, from_client_id, interaction_packet}, state) do
    interaction = Interaction.from_list(interaction_packet)
    from_client = state.clients[from_client_id]

    # Sanity check the message before processing it
    if(
      # ensure first message is announce
      (from_client.avatar_id != nil or hd(interaction.body) == "announce") and
      if interaction.from_entity == "",
        # from-entity must be set unless announce
        do: hd(interaction.body) == "announce",
        # if we do have a from-entity, make sure that entity is owned by this client
        else: {:ok, from_client_id} == PlaceStore.get_owner_id(state.store, interaction.from_entity)
    ) do
      {:ok, newstate} = handle_interaction(state, from_client, interaction)
      {:noreply, newstate}
    else
      Logger.error("Place interaction #{inspect(interaction)} from #{from_client.id} was forbidden. Sender is owned by #{inspect(PlaceStore.get_owner_id(state.store, interaction.from_entity))}")
      Server.send_interaction(state, from_client.id, Interaction.make_response(interaction, ["error", "forbidden_request", hd(interaction.body)]))
      {:noreply, state}
    end
  end

  def handle_info({:new_client, client_id}, state) do
    {:ok, state} = add_client(client_id, state)
    {:noreply, state}
  end
  def handle_info({:lost_client, client_id}, state) do
    {:ok, state} = remove_client(client_id, state)
    {:noreply, state}
  end

  # handling of client_media has been moved to server.c to see if that fixes performance.

  def handle_info({:client_clock, from_client_id, clock_packet}, state) do
    out_packet = %ClockPacket{clock_packet|
      server_time: server_time(state)
    }
    {:ok, json} = Poison.encode(out_packet)
    payload = json
    NetDaemon.netsend(
      state.mmallo,
      from_client_id,
      NetDaemon.channels.clock,
      payload
    )
    {:noreply, state}
  end

  defp server_time(state) do
    System.convert_time_unit(System.monotonic_time - state.start_time, :native, :millisecond) / 1000.0
  end

  ### Intents

  def handle_client_intent(client_id, intent, state) do
    {:noreply, %ServerState{state|
        clients: Map.update!(state.clients, client_id, fn(client) -> %ClientRef{client|
          intent: %ClientIntent{intent|
            entity_id: client.avatar_id
          }
        } end )
      }
    }
  end

  def handle_timer(state) do
    # 1. Simulate the world
    clients = Map.values(state.clients)
    intents = Enum.map(clients, fn client -> client.intent end)
    :ok = PlaceStore.simulate(state.store, intents, server_time(state))

    # 2. Broadcast new states
    old_revs = Enum.map(intents, fn intent -> intent.ack_state_rev end)
    {:ok, deltas} = PlaceStore.get_snapshot_deltas(state.store, old_revs)
    Enum.each(List.zip([clients, deltas]), fn({client, delta}) ->
      send_delta(state, client, delta)
    end)

    # 3. Schedule the next send
    tref = Process.send_after(self(), :timer, div(1000, 20))
    {:noreply, %ServerState{state|
      push_state_timer: tref
      }}
  end

  defp send_delta(state, client, delta)  do
    payload = delta
    NetDaemon.netsend(
      state.mmallo,
      client.id,
      NetDaemon.channels.statediffs,
      payload
    )
  end


  ### Interactions

  # handle "place" locally
  defp handle_interaction(state,
    from_client,
    %Interaction{
      to_entity: p
    } = interaction
  ) when p == "place" or p == "place-button"
  do
    try do
      PlaceEntity.handle_interaction(state, from_client, interaction)
    rescue
      e ->
        Logger.error("Place interaction #{inspect(interaction)} from #{from_client.id} failed terribly: #{inspect(e)}")
        Server.send_interaction(state, from_client.id, Interaction.make_response(interaction, ["error", "invalid_request", hd(interaction.body)]))
        {:ok, state}
    end
  end
  # anything else? route it to the owner.
  defp handle_interaction(state,
    from_client,
    %Interaction{
      to_entity: to
    } = interaction
  ) do
    try do
      {:ok, dest_owner_id} = PlaceStore.get_owner_id(state.store, to)
      send_interaction(state, dest_owner_id, interaction)
    rescue
      MatchError ->
        Logger.error("Failed interaction #{inspect(interaction)} to #{to} which doesn't exist or missing owner")
        Server.send_interaction(state, from_client.id, Interaction.make_response(interaction, ["error", "invalid_recipient", hd(interaction.body), to]))
    end
    {:ok, state}
  end

  # send to specific client, if you already know which client owns an entity
  def send_interaction(state, dest_client_id, interaction) do
    {:ok, json} = Jason.encode(interaction)
    payload = json
    case NetDaemon.netsend(
      state.mmallo,
      dest_client_id,
      NetDaemon.channels.commands,
      payload
    ) do
      :ok ->
        :ok
      {:error, error} ->
        Logger.error("Failed sending interaction #{inspect(interaction)} to #{dest_client_id}: #{error}")
        {:error, error}
    end
  end

  def disconnect_later(state, client, code) do
    :ok = NetDaemon.disconnect(
      state.mmallo,
      client.id,
      code
    )
  end


  ### Clients
  defp add_client(client_id,  state) do
    Logger.info("Client connected: #{client_id}")
    {
      :ok,
      %ServerState{state|
        clients: Map.put(state.clients, client_id, %ClientRef{
          id: client_id
        })
      }
    }
  end
  defp remove_client(client_id, state) do
    Logger.info("Client disconnected: #{client_id}")
    {:ok, _clientref} = Map.fetch(state.clients, client_id)
    :ok = PlaceStore.remove_entities_owned_by(state.store, client_id)
    {
      :ok,
      %ServerState{state|
        clients: Map.delete(state.clients, client_id)
      }
    }
  end
end
