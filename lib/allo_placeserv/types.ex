
defmodule PoseGrab do
  defstruct entity: "",
    grabber_from_entity_transform: Graphmath.Mat44.identity()
end

defmodule Pose do
  defstruct matrix: Graphmath.Mat44.identity(),
    grab: %PoseGrab{}
end

defimpl Poison.Decoder, for: Pose do
  # Convert matrix from list to Mat44
  def decode(value, _) do
    %Pose{
      matrix: List.to_tuple(value.matrix),
      grab: %PoseGrab{ # ?? can't get Poison.Decoder, for: PoseGrab to work
        grabber_from_entity_transform:
          if(is_tuple(value.grab.grabber_from_entity_transform), do:
            value.grab.grabber_from_entity_transform,
          else:
            List.to_tuple(value.grab.grabber_from_entity_transform)),
        entity: value.grab.entity
      }
    }
  end
end

defimpl Poison.Encoder, for: Pose do
  def encode(value, options) do
    Poison.Encoder.encode(%{
      matrix: Tuple.to_list(value.matrix),
      grab: %{
        grabber_from_entity_transform: Tuple.to_list(value.grab.grabber_from_entity_transform),
        entity: value.grab.entity
      }
    }, options)
  end
end


defmodule Poses do
  # can't use defstruct because some keys aren't regular atoms
  def __struct__() do
    %{
      :__struct__ => __MODULE__,
      :head => %Pose{},
      :torso => %Pose{},
      :"hand/left" => %Pose{},
      :"hand/right" => %Pose{},
      :root => %Pose{},
    }
  end
  def __struct__(kv) do
    :lists.foldl(fn {key, val}, acc -> Map.replace!(acc, key, val) end, Poses.__struct__(), kv)
  end
end

defmodule ClientIntent do
  defstruct entity_id: "",
    wants_stick_movement: false,
    zmovement: 0,
    xmovement: 0,
    yaw: 0,
    pitch: 0,
    poses: %Poses{},
    ack_state_rev: 0
    @type t :: %ClientIntent{entity_id: String.t(), wants_stick_movement: bool, zmovement: float, xmovement: float, yaw: float, pitch: float, poses: Poses.t(), ack_state_rev: integer}
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

  def make_response(request, body) do
    %Interaction{
      type: if(request.type=="request", do: "response", else: "one-way"),
      from_entity: request.to_entity,
      to_entity: request.from_entity,
      request_id: request.request_id,
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

defmodule ClockPacket do
  @derive [Poison.Encoder]
  defstruct client_time: 0.0,
    server_time: 0.0
end

defmodule ClientIdentity do
  @derive Jason.Encoder
  defstruct display_name: nil
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
