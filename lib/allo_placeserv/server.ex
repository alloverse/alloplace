defmodule ServerState do
  defstruct clients: %{}, # from client_id to ClientRef
    mmallo: nil,
    push_state_timer: nil,
    name: "Unnamed place",
    next_free_track: 1

  @type t :: %ServerState{
    clients: %{required(String.t()) => ClientRef.t()},
    mmallo: pid(),
    push_state_timer: TRef,
    name: String.t(),
    next_free_track: Integer.t()
  }
end

defmodule Pose do
  defstruct matrix: Graphmath.Mat44.identity()
end
defimpl Poison.Decoder, for: Pose do
  # Convert matrix from list to Mat44
  def decode(value, _options) do
    %Pose{
      matrix: List.to_tuple(value.matrix)
    }
  end
end
defimpl Poison.Encoder, for: Pose do
  def encode(value, options) do
    Poison.Encoder.encode(%{
      matrix: Tuple.to_list(value.matrix)
    }, options)
  end
end


defmodule Poses do
  # can't use defstruct because some keys aren't regular atoms
  def __struct__() do
    %{
      :__struct__ => __MODULE__,
      :head => %Pose{},
      :"hand/left" => %Pose{},
      :"hand/right" => %Pose{}
    }
  end
  def __struct__(kv) do
    :lists.foldl(fn {key, val}, acc -> Map.replace!(acc, key, val) end, Poses.__struct__(), kv)
  end
end

defmodule ClientIntent do
  defstruct entity_id: "",
    zmovement: 0,
    xmovement: 0,
    yaw: 0,
    pitch: 0,
    poses: %Poses{}
    @type t :: %ClientIntent{entity_id: String.t(), zmovement: float, xmovement: float, yaw: float, pitch: float, poses: Poses.t()}
end

defmodule Interaction do
  defstruct type: "request", # or response oneway publication
    from_entity: "",
    to_entity: "",
    request_id: "",
    body: []
  def from_list(["interaction", type, from, to, rid, body]) do
    %Interaction{
      type: type,
      from_entity: from,
      to_entity: to,
      request_id: rid,
      body: body
    }
  end
end
defimpl Jason.Encoder, for: Interaction do
  def encode(struct, opts) do
    Jason.Encode.list([
      "interaction",
      struct.type,
      struct.from_entity,
      struct.to_entity,
      struct.request_id,
      struct.body
    ], opts)
  end
end

defmodule ClientIdentity do
  @derive Jason.Encoder
  defstruct display_name: nil
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

  def init(initial_state) do
    Logger.info("Starting Alloverse Place server '#{initial_state.name}'")
    {:ok, mmallo} = MmAllonet.start_link([], self(), 31337)

    # update state and send world state @ 20hz
    {:ok, tref} = :timer.send_interval(Kernel.trunc(1000/2), self(), {:timer, 1.0/2})

    reply = MmAllonet.ping(mmallo)
    Logger.info("net replies? #{reply}")

    reply = PlaceStore.ping(AlloProcs.Store)
    Logger.info("state replies? #{reply}")

    :ok = PlaceStore.add_entity(AlloProcs.Store, %PlaceEntity{})

    { :ok,
      %ServerState{initial_state|
      push_state_timer: tref,
      mmallo: mmallo}
    }
  end

  def start_link(opts) do
    name = System.get_env("ALLOPLACE_NAME", "Unnamed place")
    GenServer.start_link(__MODULE__, %ServerState{
      name: name
    }, opts)
  end

  ### GenServer
  def handle_info({:client_intent, client_id, intent_packet}, state) do
    handle_client_intent(client_id, intent_packet, state)
  end
  def handle_info({:timer, delta}, state) do
    handle_timer(delta, state)
  end

  def handle_info({:client_interaction, from_client_id, interaction_packet}, state) do
    interaction = Interaction.from_list(interaction_packet)
    from_client = state.clients[from_client_id]
    Logger.info("From #{from_client_id}, #{inspect(interaction)}")

    # ensure valid from (note: pattern match)
    if interaction.from_entity != "" do
      {:ok, _} = PlaceStore.get_owner_id(AlloProcs.Store, interaction.from_entity)
    end

    # ensure announced
    true = (from_client.avatar_id != nil || hd(interaction.body) == "announce")

    # go handle
    {:ok, newstate} = handle_interaction(state, from_client, interaction)
    {:noreply, newstate}
  end
  def handle_info({:new_client, client_id}, state) do
    {:ok, state} = add_client(client_id, state)
    {:noreply, state}
  end
  def handle_info({:lost_client, client_id}, state) do
    {:ok, state} = remove_client(client_id, state)
    {:noreply, state}
  end

  def handle_info({:client_media, from_client_id, incoming_payload}, state) do
    # incoming message is track id as 32bit big endian integer, followed by media payload
    #<<track_id :: unsigned-big-integer-size(32), media_packet>> = incoming_payload

    # todo: lookup a LiveMediaComponent with a matching track ID and
    # assert that from_client_id owns that entity.

    # outgoing payload is same format as outgoing, so we just mirror it out to all clients
    outgoing_payload = incoming_payload

    state.clients |>
      Enum.filter(fn({_client_id, client}) -> client.id != from_client_id end) |>
      Enum.each(fn({client_id, _client}) ->
        MmAllonet.netsend(
          state.mmallo,
          client_id,
          MmAllonet.channels.media,
          outgoing_payload
        )
      end)

    {:noreply, state}
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

  def handle_timer(delta, state) do
    # 1. Simulate the world
    intents = Enum.map(Map.values(state.clients), fn client -> client.intent end)

    :ok = PlaceStore.simulate(AlloProcs.Store, delta, intents)

    # 2. Broadcast new states
    {:ok, snapshot} = PlaceStore.get_snapshot(AlloProcs.Store)
    send_snapshot(state, snapshot)
    {:noreply, state}
  end

  defp send_snapshot(state, snapshot) do
    payload = snapshot <> "\n"
    Enum.each(state.clients, fn({client_id, _client}) ->
      MmAllonet.netsend(
        state.mmallo,
        client_id,
        MmAllonet.channels.statediffs,
        payload
      )
    end)
  end


  ### Interactions

  # handle "place" locally
  defp handle_interaction(state,
    from_client,
    %Interaction{
      to_entity: "place"
    } = interaction
  ) do
    PlaceEntity.handle_interaction(state, from_client, interaction)
  end
  # anything else? route it to the owner.
  defp handle_interaction(state,
    _from_client,
    %Interaction{} = interaction
  ) do
    send_interaction(state, interaction)
    {:ok, state}
  end

  # send to an entity
  def send_interaction(state, %Interaction{
      to_entity: to
    } = interaction) do
    {:ok, dest_owner_id} = PlaceStore.get_owner_id(AlloProcs.Store, to)
    _dest_client = state.clients[dest_owner_id]
    send_interaction(state, dest_owner_id, interaction)
  end

  # send to specific client, if you already know which client owns an entity
  def send_interaction(state, dest_client_id, interaction) do
    {:ok, json} = Jason.encode(interaction)
    Logger.info("Sending interaction #{json} to #{dest_client_id}")
    payload = json <> "\n"
    :ok = MmAllonet.netsend(
      state.mmallo,
      dest_client_id,
      MmAllonet.channels.commands,
      payload
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
    :ok = PlaceStore.remove_entities_owned_by(AlloProcs.Store, client_id)
    {
      :ok,
      %ServerState{state|
        clients: Map.delete(state.clients, client_id)
      }
    }
  end
end
