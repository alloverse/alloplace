defmodule ServerState do
  defstruct clients: %{}, # client_id to ClientRef
    mmallo: nil,
    push_state_timer: nil # TRef
end

defmodule ClientIntent do
  @derive Jason.Encoder
  defstruct zmovement: 0,
    xmovement: 0,
    yaw: 0,
    pitch: 0
end

defmodule ClientIntentPacket do
  @derive Jason.Encoder
  defstruct intent: %ClientIntent{}
end

defmodule ClientRef do
  @enforce_keys [:id, :avatar_id]
  defstruct id: nil,
    avatar_id: nil,
    intent: %ClientIntent{}
end

defmodule AlloPlaceserv.Server do
  @moduledoc """
  I think this class starts out handling network and manipulating the world state, while
  placestore actually holds it.
  """
  use GenServer
  require Logger

  @spec init(ServerState.t()) :: {:ok, ServerState.t()}
  def init(initial_state) do
    Logger.info("Starting Alloverse Place server")
    {:ok, mmallo} = AlloPlaceserv.MmAllonet.start_link([], 31337, self())
    {:ok, tref} = :timer.send_interval(Kernel.trunc(1.0/20), self(), {:timer, 1000/20})
    reply = AlloPlaceserv.MmAllonet.ping(mmallo)
    Logger.info("Reply #{reply}")

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

  def handle_info({:timer, delta}, state) do
    # 1. Transform intents into forces
    Enum.each(state.clients, fn({_, client}) ->
      intent = client.intent
      :ok = AlloPlaceserv.PlaceStore.update_entity(AlloPlaceserv.PlaceStore, client.avatar_id, "transform", fn(t) ->
        %TransformComponent{t|
          position: %AlloVector{t.position|
            x: t.position.x + intent.xmovement*delta,
            z: t.position.z + intent.zmovement*delta
          }
        }
      end)
    end)

    # 2. Transform forces into position and rotation changes
    # ...todo, and make intents modify physprops, not transform

    # 3. Broadcast new states
    {:ok, snapshot} = AlloPlaceserv.PlaceStore.get_snapshot(AlloPlaceserv.Store)
    {:ok, json} = Jason.encode(snapshot)
    payload = json <> "\n"
    Enum.each(state.clients, fn({client_id, client}) ->
      AlloPlaceserv.MmAllonet.netsend(mmallo, client_id, 0, payload)
    end)
    {:noreply, state}
  end


  ### Privates
  defp generate_id() do
    Enum.take_random(?a..?z, 10)
  end

  defp add_client(client_id,  state) do
    avatar_id = generate_id()
    :ok = AlloPlaceserv.PlaceStore.add_entity(AlloPlaceserv.Store, %Entity{
      id: avatar_id
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
    Process.demonitor(clientref.monitor)
    :ok = AlloPlaceserv.PlaceStore.remove_entity(AlloPlaceserv.Store, client_id)
    {
      :ok,
      %ServerState{state|
        clients: Map.delete(state.clients, client_id)
      }
    }
  end
end
