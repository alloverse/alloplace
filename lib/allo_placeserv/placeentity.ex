
defmodule PlaceEntity do
    @moduledoc """
    The server-side entity that represents the place itself.
    You send RPCs to it to change the room itself, e g to spawn new entites.
    Must duck-type Entity.
    """
    require Logger

    @derive Jason.Encoder
    defstruct id: "place",
        owner: "",
        components: %{
            transform: %TransformComponent{}
        }

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["announce", "version", 1, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce: #{inspect(interaction)}")

        avatars = entities_for_desc(avatardesc, client.id, %RelationshipsComponent{})
        true = Enum.all?(
            Enum.map(avatars, fn avatar ->
               PlaceStore.add_entity(AlloProcs.Store, avatar)
            end), fn result ->
               result == :ok
            end
        )
        avatar = hd(avatars)

        response = %Interaction {
            from_entity: "place",
            to_entity: interaction.from_entity,
            request_id: interaction.request_id,
            type: "response",
            body: ["announce", avatar.id, server_state.name]
        }
        Server.send_interaction(server_state, client.id, response)

        {:ok, %ServerState{server_state|
            clients: Map.update!(server_state.clients, client.id, fn(client) -> %ClientRef{client|
                avatar_id: avatar.id,
                identity: identity
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

    def handle_interaction(server_state,
        _client,
        %Interaction{
            :type => "request"
        } = interaction
    ) do
        Logger.info("Unhandled place request interaction: #{inspect(interaction)}")
        response = %Interaction {
            from_entity: "place",
            to_entity: interaction.from_entity,
            request_id: interaction.request_id,
            type: "response",
            body: [hd(interaction.body), "failed", "#{server_state.name} doesn't understand #{hd(interaction.body)}"]
        }
        Server.send_interaction(server_state, response)

        {:ok, server_state}
    end
    def handle_interaction(server_state,
        _client,
        %Interaction{
        } = interaction
    ) do
        Logger.info("Unhandled place interaction: #{inspect(interaction)}")
        {:ok, server_state}
    end


    defp entities_for_desc(desc, owner, relationships) do
        {childDescs, thisDesc} = Map.pop(desc, :children, [])
        thisEnt = %Entity{
            id: Allomisc.generate_id(),
            owner: owner,
            components: Map.merge(thisDesc, %{
                transform: %TransformComponent{},
                relationships: relationships
            })
        }
        childEnts = Enum.flat_map(childDescs, fn childDesc ->
            entities_for_desc(childDesc, owner, %RelationshipsComponent{parent: thisEnt.id})
        end)
        List.insert_at(childEnts, 0, thisEnt)
    end
end
