
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
            geometry: %{
                type: "inline",
                           #  bl                 # br                 #tl                    #tr
                vertices: [[0.2, 0.8, -0.2],     [0.2, 0.8, 0.2],     [-0.2, 1.0, -0.2],     [-0.2, 1.0, 0.2]],
                uvs:      [[0.0, 0.0],           [1.0, 0.0],          [0.0, 1.0],            [1.0, 1.0]],
                triangles: [[0, 3, 1], [0, 2, 3]],
                texture: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsQAAA7EAZUrDhsAAAM6SURBVHhe7Zq9b9NAGIdfJ2lSqlYCNtQVhGBkKOIPQOJjQEgMTBUDYkDqVDb+BqZuwFKpCxJiQRVCZWBKF9S1c4QQXfgKH21omuD3cm+4nBz7fL472z0/Uvq6kXr277n37MZxsLuzOQSPqfHqLZUAXr2lEsCrtxgVcOHSTfayhY3xjVwG6aCuPhkNtbUasBqOzWpWcPxGOFX9AX8jxNTYmQTIwUVIAqJ7sDj+qdkafDsYwOeV6/xdgI/dfVhaf8+2s4rQEiC2YVR4Ed1uoH2IwWXOrL3hW/oiUgm4dvshdDodtp0UXEZVhEpwmSwilAXEtbsqccsCx5+fCeDX4TBVeBESkUZCooA07a6KLEJn1uNII2KqABvBZUQRpsITqssiUoCJdo+Dgj9YvgWt5gysPX/JfjctAUkSMSEAg9Nlx0Z4DE7X85X7d/i7/3EhQpYwFuBq1qOCi6CEqGu/CaK6AY9qeLJVg+89e7OOJAWXcdUNTIDN4Avzc3Dv7g22nZbNrTZ82duDH+Hk2OoG4wIoOJJ21qdhoxusCNBtd1VMijAqwHZwEZTQrAfw90j/P0bEiAAb7a5K1m7ILMDlrMehK0JbQFGCi5AERFUECdC6JVak8EiW46luivJaenS7oOoAXr2lEsCrd1xZPM2qtwK2P31l1VsBq0tnWfVWwKPL51itToL4Q/xU5xtVB/DqLZUAXo8FC031c9n4fgB9QYAnwrKfDBu15OPH4BefvWXbmJ11AG6IIspKfzD9zla3dzie9Xb79TjvxBIgEWXthmkdgMHPP303MdFE5DmgrCL2+5MdgMHxFRWciD0J0h99eFwvhYgTjdExyus8jsQnRAjxgYmi3RQlNjZesW+VkaTghLIAoqgi6Na4anAitQARkpGnCPE7gbThkUwCEJQwG669g/AE5FIEBp8L9/sn3K9OcCKzAMJlN+i2exTGBBA2RZgMThgXgKCEVj2A3pGZZYHB6bkhk+ERKwII6gZEV4SNWRexKoDQWRa2gxNOBBAqIro/f8P6i9GHFtvhEacCEJRAj7jIIlzNuohzAYTYDXkEJ3ITgJCEPIITuQooAsfqnqAOlQBevcVzAQD/ACwg7buhFwAGAAAAAElFTkSuQmCC"
            }
        }

    def init() do
        PlaceStore.add_entity(AlloProcs.Store, %PlaceEntity{})
        PlaceStore.add_entity(AlloProcs.Store, %Entity{
            id: "place-button",
            components: %{
                transform: %TransformComponent{
                    matrix: Graphmath.Mat44.make_translate(0, 0.9, 0)
                },
                relationships: %RelationshipsComponent {
                    parent: "place"
                },
                geometry: %{
                    type: "inline",
                               #  bl                 # br                 #tl                    #tr
                    vertices: [[0.1, 0.0, -0.1],     [0.1, 0.0, 0.1],     [-0.1, 0.1, -0.1],     [-0.1, 0.1, 0.1]],
                    uvs:      [[0.0, 0.0],           [1.0, 0.0],          [0.0, 1.0],            [1.0, 1.0]],
                    triangles: [[0, 3, 1], [0, 2, 3]],
                    texture: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAD8SURBVGhD7c/LCcJgFERhq7Qgy3CfRXoQXItNGYmEeMyQbEbuhYFv9T9gzun6fPR1HofGAdP6xgHz+q4By/qWAev1/QKwftIpANNnbQKwe9EjAKPXGgRgMVQPwNxfpQOwddPRgMv99mcYqiTABkOVBNhgqJIAGwxVEmCDoUoCbDBUSYANhioJsMFQJQE2GKokwAZDlQTYYKiSABsMVRJgg6FKAmwwVEmADYYqCbDBUCUBNhiqJMAGQ5UE2GCokgAbDFUSYIOhytEAfKvjUAD+lLIfgA/V7ATgdUEyAO/K2g7Ao8o2AvCiOAbgur6vANy18AnAaSPvABx1Mg4vbr0dVP2tGoQAAAAASUVORK5CYII="
                },
                collider: %{
                    type: "box",
                    width: 0.2, height: 0.2, depth: 0.2
                }
            }
        })
    end

    def handle_interaction(server_state,
        client,
        %Interaction{
            :body => ["announce", "version", 1, "identity", identity, "spawn_avatar", avatardesc]
        } = interaction
    ) do
        Logger.info("Client announce for client #{client.id}: #{inspect(interaction)}")

        avatars = entities_for_desc(avatardesc, client.id, %RelationshipsComponent{})
        true = Enum.all?(
            Enum.map(avatars, fn avatar ->
               PlaceStore.add_entity(AlloProcs.Store, avatar)
            end), fn result ->
               result == :ok
            end
        )
        avatar = hd(avatars)

        response = Interaction.make_response(interaction, "place", ["announce", avatar.id, server_state.name])
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

        :ok = PlaceStore.update_entity(AlloProcs.Store,
            interaction.from_entity,
            %{ live_media: media_comp}
        )
        response = Interaction.make_response(interaction, "place", ["allocate_track", "ok", track_id])
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
        client,
        %Interaction{
            :body => ["poke", buttonDown]
        } = interaction
    ) do
        response = Interaction.make_response(interaction, "place-button", ["poke", "ok"])
        Server.send_interaction(server_state, client.id, response)
        :ok = PlaceStore.update_entity(AlloProcs.Store,
            "place-button",
            %{
                transform: %TransformComponent{
                    matrix: Graphmath.Mat44.make_translate(0, (if buttonDown, do: 0.88, else: 0.9), 0)
                },
            }
        )


        {:ok, server_state}
    end


    def handle_interaction(server_state,
        _client,
        %Interaction{
            :body => ["lol", _a, _b, _c]
        } = interaction
    ) do
        response = Interaction.make_response(interaction, "place", ["yeah, very funny"])
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
        response = Interaction.make_response(interaction, "place",
            [hd(interaction.body), "failed", "#{server_state.name} doesn't understand #{hd(interaction.body)}"]
        )
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
