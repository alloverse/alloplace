
defmodule PlaceEntity do
    @moduledoc """
    The server-side entity that represents the place itself.
    You send RPCs to it to change the room itself, e g to spawn new entites.
    """
    require Logger

    @derive Jason.Encoder
    defstruct id: "place",
        components: %{}

    def handle_interaction(state,
        client_id,
        %Interaction{
            :body => ["announce", "version", 1, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce: #{inspect(interaction)}")

        avatar_id = Util.generate_id()
        :ok = PlaceStore.add_entity(AlloProcs.Store, %Entity{
          id: avatar_id,
          owner: client_id,
          components: avatardesc
        })

        {
            :ok,
            %ServerState{state|
                clients: Map.update!(state.clients, client_id, fn(client) -> %ClientRef{client|
                    identity: identity,
                    avatar_id: avatar_id
                } end )
            }
        }
    end

    def handle_interaction(server_state,
        %Interaction{
            :body => ["lol", _a, _b, _c]
        } = interaction
    ) do
        response = %Interaction {
            from_entity: "place",
            to_entity: interaction.from_entity,
            request_id: interaction.request_id,
            type: "response",
            body: ["ok"]
        }

        Server.send_interaction(server_state, response)
    end

end
