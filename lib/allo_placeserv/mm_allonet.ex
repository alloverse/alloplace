defmodule AllonetState do
  defstruct udpport: 31337,
    delegate: nil, # pid()
    daemon: nil # DaemonState
end


defmodule ClientIntentPacket do
    defstruct cmd: "intent",
      intent: %ClientIntent{}
end

defmodule MmAllonet do
  use GenServer
  require Logger

  def start_link(opts, delegate, udpport) do
    GenServer.start_link(__MODULE__, %AllonetState{
      delegate: delegate,
      udpport: udpport
    }, opts)
  end

  def init(initial_state) do
    {:ok, %AllonetState{initial_state|
      daemon: Daemon.setup("priv/AlloNetPort")
    }}
  end

  @channel_statediffs 0
  @channel_commands 1
  @channel_assets 2
  @channel_media 3
  def channels, do: %{
    statediffs: @channel_statediffs,
    commands: @channel_commands,
    assets: @channel_assets,
    media: @channel_media
  }

  @doc "Send raw byte payload to client"
  def netsend(this, client_id, channel, payload) do
    GenServer.call(this, {:ccall, :send, {client_id, channel, payload}})
  end
  @doc "Hard shutdown of all systems"
  def stop(this) do
    :ok = GenServer.call(this, {:ccall, :stop, {}})
    GenServer.call(this, :stop)
  end
  @doc "Gracefully disconnect all clients"
  def disconnect(this, client_id) do
    GenServer.call(this, {:ccall, :disconnect, {client_id}})
  end
  @doc "Test that underlying allonet process is alive"
  def ping(this) do
    GenServer.call(this, {:ccall, :ping, {}})
  end

  def handle_call({:ccall, cmd, args}, from, state) do
    {:ok, daemon} = Daemon.call_to_c(cmd, args, from, state.daemon)
    { :noreply,
      %AllonetState{state|
        daemon: daemon,
      }
    }
  end

  def handle_call(:stop, _from, state) do
    :ok = Daemon.stop(state.daemon)
    { :reply,
      :ok,
      %AllonetState{state|
        delegate: nil
      }
    }
  end

  def handle_info({_from, {:data, data}}, state) do
    {payload, dstate} = Daemon.handle_call_from_c(data, state.daemon)

    case payload do
      {:client_connected, client_id} ->
        send(state.delegate, {:new_client, client_id})
      {:client_disconnected, client_id} ->
        send(state.delegate, {:lost_client, client_id})
      {:client_sent, client_id, channel, payload} ->
        parse_payload(client_id, channel, payload, state)
      :ok -> :ok
    end

    {
      :noreply,
      %AllonetState{state|
        daemon: dstate
      }
    }
  end

  # why is :EXIT callled but not this?
  def handle_info({_port, {:exit_status, status}}, state) do
    raise("AllonetPort died unexpectedly: #{status}")
    {
      :noreply,
      state
    }
  end

  def handle_info({:EXIT, _port, mode}, state) do
    raise("AllonetPort died unexpectedly: #{mode}")
    {
      :noreply,
      state
    }
  end

  defp parse_payload(client_id, @channel_statediffs, payload, state) do
    packet = Poison.decode!(payload, as: %ClientIntentPacket{}, keys: :atoms)

    send(state.delegate, {:client_intent, client_id, packet.intent})
    {
      :noreply,
      state
    }
  end
  defp parse_payload(client_id, @channel_commands, payload, state) do
    # todo: :atoms is dangerous; make sure data conforms to intent/interaction record first
    packet = Jason.decode!(payload, [{:keys, :atoms}])
    send(state.delegate, {:client_interaction, client_id, packet})
    {
      :noreply,
      state
    }
  end
  defp parse_payload(client_id, @channel_media, payload, state) do
    send(state.delegate, {:client_media, client_id, payload})
    {
      :noreply,
      state
    }
  end

end
