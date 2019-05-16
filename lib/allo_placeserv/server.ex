defmodule ServerState do
  defstruct clients: %{}, # from client_id to ClientRef
    mmallo: nil,
    push_state_timer: nil

  @type t :: %ServerState{
    clients: %{required(String.t()) => ClientRef.t()},
    mmallo: pid(),
    push_state_timer: TRef
  }
end

defmodule ClientIntent do
  @derive Jason.Encoder
  defstruct zmovement: 0,
    xmovement: 0,
    yaw: 0,
    pitch: 0
    @type t :: %ClientIntent{zmovement: float, xmovement: float, yaw: float, pitch: float}
end

defmodule ClientIntentPacket do
  @derive Jason.Encoder
  defstruct intent: %ClientIntent{}
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
  defstruct displayName: ""
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
    Logger.info("Starting Alloverse Place server")
    {:ok, mmallo} = MmAllonet.start_link([], self(), 31337)

    # update state and send world state @ 20hz
    {:ok, tref} = :timer.send_interval(Kernel.trunc(1000/20), self(), {:timer, 1.0/20})

    reply = MmAllonet.ping(mmallo)
    Logger.info("C replies? #{reply}")

    :ok = PlaceStore.add_entity(AlloProcs.Store, %PlaceEntity{})

    { :ok,
      %ServerState{initial_state|
      push_state_timer: tref,
      mmallo: mmallo}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %ServerState{

    }, opts)
  end

  ### GenServer
  def handle_info({:client_intent, client_id, intent_packet}, state) do
    handle_client_intent(client_id, intent_packet, state)
  end
  def handle_info({:timer, delta}, state) do
    handle_timer(delta, state)
  end
  def handle_info({:client_interaction, client_id, interaction_packet}, state) do
    interaction = Interaction.from_list(interaction_packet)
    {:ok, state} = handle_interaction(state, client_id, interaction)
    {:noreply, state}
  end
  def handle_info({:new_client, client_id}, state) do
    {:ok, state} = add_client(client_id, state)
    {:noreply, state}
  end
  def handle_info({:lost_client, client_id}, state) do
    {:ok, state} = remove_client(client_id, state)
    {:noreply, state}
  end

  ### Intents

  def handle_client_intent(client_id, intent_packet, state) do
    {:noreply, %ServerState{state|
        clients: Map.update!(state.clients, client_id, fn(client) -> %ClientRef{client|
          intent: intent_packet.intent
        } end )
      }
    }
  end

  def handle_timer(delta, state) do
    # 1. Transform intents into forces
    Enum.each(state.clients, fn({_, client}) ->
      intent = client.intent
      :ok = PlaceStore.update_entity(AlloProcs.Store, client.avatar_id, :transform, fn(t) ->
        intentvec = Graphmath.Vec3.rotate(
          Graphmath.Vec3.create(intent.xmovement, 0, intent.zmovement),
          Graphmath.Vec3.create(0,1,0),
          intent.yaw
        )
        #Logger.info("Rotating intent #{inspect(intent)} becomes #{inspect(intentvec)}")
        newpos = Graphmath.Vec3.add(Allomath.a2gvec(t.position), Graphmath.Vec3.scale(intentvec, delta))
        %TransformComponent{t|
          position: Allomath.g2avec(newpos),
          rotation: %AlloVector{
            x: intent.pitch,
            y: intent.yaw,
            z: 0
          }
        }
      end)
    end)

    # 2. Transform forces into position and rotation changes
    # ...todo, and make intents modify physprops, not transform

    # 3. Broadcast new states
    {:ok, snapshot} = PlaceStore.get_snapshot(AlloProcs.Store)
    send_snapshot(state, snapshot)
    {:noreply, state}
  end

  defp send_snapshot(state, snapshot) do
    {:ok, json} = Jason.encode(snapshot)
    #Logger.info("World: #{inspect(snapshot)}")
    payload = json <> "\n"
    Enum.each(state.clients, fn({client_id, _client}) ->
      :ok = MmAllonet.netsend(
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
    {:ok, owner_id} = PlaceStore.get_owner_id(AlloProcs.Store, to)
    _client = state.clients[owner_id]
    send_interaction(state, owner_id, interaction)
  end

  # send to specific client, if you already know which client owns an entity
  def send_interaction(state, client_id, interaction) do
    Logger.info("Sending interaction name #{hd(interaction.body)} to #{client_id}")
    {:ok, json} = Jason.encode(interaction)
    payload = json <> "\n"
    :ok = MmAllonet.netsend(
      state.mmallo,
      client_id,
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
