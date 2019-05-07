
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
        %Interaction{
            :body => ["announce", client_version, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce: #{interaction}")
    end

end 