
defmodule PlaceEntity do
    @moduledoc """
    The server-side entity that represents the place itself.
    You send RPCs to it to change the room itself, e g to spawn new entites.
    """
    require Logger

    @derive Jason.Encoder
    defstruct id: "place",
        components: %{}

    def handle_interaction(server_state, 
        client,
        %Interaction{
            :body => ["announce", "version", 1, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce: #{inspect(interaction)}")

        avatar_id = Allomisc.generate_id()
        :ok = PlaceStore.add_entity(AlloProcs.Store, %Entity{
            id: avatar_id,
            owner: client.id
        })

        response = %Interaction {
            from_entity: "place",
            to_entity: interaction.from_entity,
            request_id: interaction.request_id,
            type: "response",
            body: ["announce", avatar_id]
        }
        Server.send_interaction(server_state, client.id, response)

        {:ok, %ServerState{server_state|
            clients: Map.update!(server_state.clients, client.id, fn(client) -> %ClientRef{client|
                avatar_id: avatar_id
            } end )
        }
    }
    end

    def handle_interaction(server_state, 
        _client,
        %Interaction{
            :body => ["lol", _a, _b, _c]
        } = interaction
    ) do
        response = %Interaction {
            from_entity: "place",
            to_entity: interaction.from_entity,
            request_id: interaction.request_id,
            type: "response",
            body: ["yeah, very funny"]
        }
        Logger.info("Got lol: #{inspect(interaction)}")

        Server.send_interaction(server_state, response)

        {:ok, server_state}
    end

end
