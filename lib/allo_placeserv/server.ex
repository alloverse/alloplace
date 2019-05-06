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

defmodule ClientRef do
  @enforce_keys [:id, :avatar_id]
  defstruct id: nil,
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

    {:ok, %ServerState{initial_state|
      push_state_timer: tref,
      mmallo: mmallo}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %ServerState{

    }, opts)
  end

  def handle_info({:new_client, client_id}, state) do
    Logger.info("Client connected: #{client_id}")
    {:ok, state} = add_client(client_id, state)
    {:noreply, state}
  end

  def handle_info({:lost_client, client_id}, state) do
    Logger.info("Client disconnected: #{client_id}")
    {:ok, state} = remove_client(client_id, state)
    {:noreply, state}
  end

  def handle_info({:client_intent, client_id, intent_packet}, state) do
    {:noreply, %ServerState{state|
        clients: Map.update!(state.clients, client_id, fn(client) -> %ClientRef{client|
          intent: intent_packet.intent
        } end )
      }
    }
  end

  def handle_info({:client_interaction, _client_id, interaction_packet}, state) do
  Logger.info("Unhandled interaction: #{inspect(interaction_packet)}")
    {:noreply, state}
  end

  @spec handle_info({:timer, float()}, ServerState.t()) :: {:noreply, ServerState.t()}
  def handle_info({:timer, delta}, state) do
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

  ### Privates
  defp generate_id() do
    to_string(Enum.take_random(?a..?z, 10))
  end

  defp add_client(client_id,  state) do
    avatar_id = generate_id()
    :ok = PlaceStore.add_entity(AlloProcs.Store, %Entity{
      id: avatar_id
    })

    send_interaction(state, client_id, %Interaction{
      type: "oneway",
      from_entity: "place",
      to_entity: "",
      request_id: "",
      body: ["your_avatar", avatar_id]
    })
    

    {
      :ok,
      %ServerState{state|
        clients: Map.put(state.clients, client_id, %ClientRef{
          id: client_id,
          avatar_id: avatar_id
        })
      }
    }
  end
  defp remove_client(client_id, state) do
    {:ok, clientref} = Map.fetch(state.clients, client_id)
    :ok = PlaceStore.remove_entity(AlloProcs.Store, clientref.avatar_id)
    {
      :ok,
      %ServerState{state|
        clients: Map.delete(state.clients, client_id)
      }
    }
  end

  defp send_snapshot(state, snapshot) do
    {:ok, json} = Jason.encode(snapshot)
    #Logger.info("World: #{inspect(snapshot)}")
    payload = json <> "\n"
    Enum.each(state.clients, fn({client_id, _client}) ->
      MmAllonet.netsend(
        state.mmallo,
        client_id,
        MmAllonet.channels.statediffs,
        payload
      )
    end)
  end

  defp send_interaction(state, client_id, interaction) do
    {:ok, json} = Jason.encode(interaction)
    payload = json <> "\n"
    MmAllonet.netsend(
      state.mmallo,
      client_id,
      MmAllonet.channels.commands,
      payload
    )
  end
end
