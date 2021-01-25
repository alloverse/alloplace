
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
            transform: %TransformComponent{},
        },
        clock: %{
            time: 0.0
        }

    def init(store) do
        PlaceStore.add_entity(store, %PlaceEntity{})
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["announce", "version", 3, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce for client #{client.id}: #{inspect(interaction)}")

        avatars = entities_for_desc(avatardesc, client.id, %RelationshipsComponent{})
        true = Enum.all?(
            Enum.map(avatars, fn avatar ->
               PlaceStore.add_entity(server_state.store, avatar)
            end), fn result ->
               result == :ok
            end
        )
        avatar = hd(avatars)

        response = Interaction.make_response(interaction, ["announce", avatar.id, server_state.name])
        Server.send_interaction(server_state, client.id, response)

        {:ok, %ServerState{server_state|
            clients: Map.update!(server_state.clients, client.id, fn(client) -> %ClientRef{client|
                avatar_id: avatar.id,
                identity: identity
            } end )
        }}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["announce", "version", old_version, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce for client #{client.id}: using old version #{old_version}! Disconnecting.")
        # 1003 = alloerror_outdated_version, comes from client.h
        Server.disconnect_later(server_state, client, 1003)
        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["change_components", eid, "add_or_change", changelist, "remove", removelist]
        } = interaction
    ) do
        clientId = client.id
        {:ok, ^clientId} = PlaceStore.get_owner_id(server_state.store, eid)

        :ok = PlaceStore.update_entity(server_state.store, eid, changelist, removelist)

        response = Interaction.make_response(interaction, ["change_components", "ok"])
        Server.send_interaction(server_state, client.id, response)

        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["spawn_entity", edesc]
        } = interaction
    ) do

        entities = entities_for_desc(edesc, client.id, %RelationshipsComponent{})
        true = Enum.all?(
            Enum.map(entities, fn entity ->
               PlaceStore.add_entity(server_state.store, entity)
            end), fn result ->
               result == :ok
            end
        )
        root_entity = hd(entities)

        response = Interaction.make_response(interaction, ["spawn_entity", root_entity.id])
        Server.send_interaction(server_state, client.id, response)

        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["remove_entity", eid, mode]
        } = interaction
    ) do
        :ok = PlaceStore.remove_entity(server_state.store, eid, mode)
        response = Interaction.make_response(interaction, ["remove_entity", "ok"])
        Server.send_interaction(server_state, client.id, response)

        {:ok, server_state}
    end
    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["remove_entity", eid]
        } = interaction
    ) do
        handle_interaction(server_state, client, %Interaction{interaction|
            :body => ["remove_entity", eid, "cascade"]
        })
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["allocate_track", media_type, sample_rate, channel_count, media_format]
        } = interaction
    ) do
        track_id = server_state.next_free_track
        Logger.info("Allocating media track ##{track_id} to #{interaction.from_entity}")

        media_comp = %LiveMediaComponent{
            type: media_type,
            track_id: track_id,
            sample_rate: sample_rate,
            channel_count: channel_count,
            format: media_format
        }

        :ok = PlaceStore.update_entity(server_state.store,
            interaction.from_entity,
            %{ live_media: media_comp},
            []
        )
        response = Interaction.make_response(interaction, ["allocate_track", "ok", track_id])
        Server.send_interaction(server_state, client.id, response)

        {:ok, %ServerState{server_state|
            next_free_track: track_id + 1,
        }}
    end

    def handle_interaction(server_state,
        _client,
        %Interaction{
            :body => ["point", [_ax, _ay, _az], [_bx, _by, _bz]]
        }
    ) do
        {:ok, server_state}
    end

    def handle_interaction(server_state,
    _client,
        %Interaction{
            :body => ["point-exit"]
        }
    ) do
        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["poke", buttonDown]
        } = interaction
    ) do
        response = Interaction.make_response(interaction, ["poke", "ok"])
        Server.send_interaction(server_state, client.id, response)
        if buttonDown == false do
            3 = 4
        end
        :ok = PlaceStore.update_entity(server_state.store,
            "place-button",
            %{
                transform: %TransformComponent{
                    matrix: Graphmath.Mat44.make_translate(0, (if buttonDown, do: 0.88, else: 0.9), 0)
                },
            },
            []
        )


        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["launch_app", appname]
        } = interaction
    ) when appname == "jukebox" or appname == "drawing-board" or appname == "clock" or appname == "fileviewer"
    do
        Logger.info("Launching app #{appname}")

        # please don't judge me
        spawn fn ->
            System.cmd("bash", ["-c", "cd alloapps/#{appname}; ./allo/assist run alloplace://localhost"])
        end

        response = Interaction.make_response(interaction, ["launch_app", "ok"])
        Server.send_interaction(server_state, client.id, response)

        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["lol", _a, _b, _c]
        } = interaction
    ) do
        response = Interaction.make_response(interaction, ["yeah, very funny"])
        Logger.info("Got lol: #{inspect(interaction)}")

        Server.send_interaction(server_state, client.id, response)

        {:ok, server_state}
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :type => "request"
        } = interaction
    ) do
        Logger.info("Unhandled place request interaction: #{inspect(interaction)}")
        response = Interaction.make_response(interaction,
            ["error", "#{server_state.name} doesn't understand #{hd(interaction.body)}"]
        )
        Server.send_interaction(server_state, client.id, response)

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
            components: Map.merge(%{
                transform: %TransformComponent{},
                relationships: relationships
            }, thisDesc)
        }
        childEnts = Enum.flat_map(childDescs, fn childDesc ->
            entities_for_desc(childDesc, owner, %RelationshipsComponent{parent: thisEnt.id})
        end)
        List.insert_at(childEnts, 0, thisEnt)
    end
end
