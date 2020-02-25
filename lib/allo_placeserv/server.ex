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
  defstruct zmovement: 0,
    xmovement: 0,
    yaw: 0,
    pitch: 0,
    poses: %Poses{}
    @type t :: %ClientIntent{zmovement: float, xmovement: float, yaw: float, pitch: float, poses: Poses.t()}
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
    intent: %ClientIntent{},
    audio_track_id: 0
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
      {:ok, from_client_id} = PlaceStore.get_owner_id(AlloProcs.Store, interaction.from_entity)
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

  def handle_info({:client_media, from_client_id, media_packet}, state) do
    from_client = state.clients[from_client_id]
    track_id = from_client.audio_track_id
    
    # Check if we need to allocate a new track ID for this client
    new_state = case from_client.audio_track_id do
      0 -> 
        track_id = state.next_free_track
        Logger.info("Allocating media track #{track_id} to client #{from_client_id}")
        # yeah we do. update both the avatar entity's component, and the cached clientref track id.
        %ServerState{state|
          clients: Map.update!(state.clients, from_client_id, fn(client) ->
            :ok = PlaceStore.update_entity(AlloProcs.Store, client.avatar_id, :live_media, fn(m) ->
              %{m| 
                track_id: track_id
              }
            end)
            %ClientRef{client|
              audio_track_id: track_id
            }
          end),
          next_free_track: track_id + 1
        }
      _ -> state
    end

    # message is track id as 32bit big endian integer, followed by the full packet
    outgoing_payload = <<track_id::unsigned-big-integer-size(32)>> <> media_packet

    state.clients |>
      Enum.filter(fn({client_id, client}) -> client.id != from_client_id end) |>
      Enum.each(fn({client_id, _client}) ->
        MmAllonet.netsend(
          state.mmallo,
          client_id,
          MmAllonet.channels.media,
          outgoing_payload
        )
      end)

    {:noreply, new_state}
  end

  ### Intents

  def handle_client_intent(client_id, intent, state) do
    {:noreply, %ServerState{state|
        clients: Map.update!(state.clients, client_id, fn(client) -> %ClientRef{client|
          intent: intent
        } end )
      }
    }
  end

  def handle_timer(delta, state) do
    # 1. Transform intents into forces
    state.clients |> Enum.filter(fn {_, client} ->
      client.avatar_id != nil
    end) |> Enum.each(fn({_, client}) ->
      # Go through each client intent and update the main avatar entity accordingly.
      intent = client.intent
      :ok = PlaceStore.update_entity(AlloProcs.Store, client.avatar_id, :transform, fn(t) ->
        # move at 1m/s
        distance = delta * 1.0

        # Intent movement is camera yaw-relative
        movement = 
          Graphmath.Mat44.multiply(
            Graphmath.Mat44.make_translate(intent.xmovement * distance, 0, intent.zmovement * distance),
            Graphmath.Mat44.make_rotate_y(intent.yaw)
          )
        
        # Discard everything in old matrix except position...
        {x, y, z} = Graphmath.Mat44.transform_point(t.matrix, Graphmath.Vec3.create())
        # .. then add old position, intent movement, and replace rotation with intent rotation.
        matrix = Graphmath.Mat44.multiply(
          Graphmath.Mat44.multiply(
            Graphmath.Mat44.make_translate(x, y, z),
            movement
          ),
          Graphmath.Mat44.make_rotate_y(intent.yaw)
        )
        %TransformComponent{t|
          matrix: matrix
        }
      end)

      # Go through each client intent pose and find matching entities if any, and override their transforms.
      intent.poses
        |> Map.from_struct()
        |> Enum.filter(fn {_poseName, pose} -> !is_nil(pose) end)
        |> Enum.each(fn {poseName, pose} ->
          poseNameStr = Atom.to_string(poseName)
          case PlaceStore.find_entity(AlloProcs.Store, fn {_id, e}  ->
            e.owner == client.id && Map.get(e.components, :intent, %IntentComponent{}).actuate_pose == poseNameStr
          end) do
          {:error, :notfound} -> nil
          {:ok, entity} ->
            :ok = PlaceStore.update_entity(AlloProcs.Store, entity.id, :transform, fn(_) ->
              %TransformComponent{
                matrix: pose.matrix
              }
            end)
          end
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
