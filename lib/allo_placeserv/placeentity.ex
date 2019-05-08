
defmodule PlaceEntity do
    @moduledoc """
    The server-side entity that represents the place itself.
    You send RPCs to it to change the room itself, e g to spawn new entites.
    """
    require Logger

    @derive Jason.Encoder
    defstruct id: "place",
        components: %{}

    def handle_interaction(_server_state, 
        %Interaction{
            :body => ["announce", _client_version, "identity", _identity, "spawn_avatar", _avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce: #{interaction}")
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