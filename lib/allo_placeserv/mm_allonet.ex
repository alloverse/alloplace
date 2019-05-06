defmodule AllonetState do
  defstruct udpport: 31337,
    delegate: nil, # pid()
    port: nil, # port()
    next_request_id: 1, # int()
    outstanding_requests: %{} # int() -> pid()
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
    Process.flag(:trap_exit, true)
    port = Port.open({:spawn, "priv/AllonetPort"}, [
      {:packet, 2},
      :binary,
      :nouse_stdio
    ])
    Process.link port

    {:ok, %AllonetState{initial_state|
      port: port
    }}
  end

  @channel_statediffs 0
  @channel_commands 1
  def channels, do: %{
    statediffs: @channel_statediffs,
    commands: @channel_commands
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
    rid = state.next_request_id
    msg = {cmd, rid, args}
    send(state.port, {self(), {:command, :erlang.term_to_binary(msg)}})
    { :noreply,
      %AllonetState{state|
        next_request_id: rid+1,
        outstanding_requests: Map.put(state.outstanding_requests, rid, from)
      }
    }
  end

  def handle_call(:stop, _from, state) do
    send(state.port, {self(), :close})
    :ok = receive do
      {_port, :closed} ->
        :ok
      after 1_000 ->
        :timeout
    end
    { :reply,
      :ok,
      %AllonetState{state|
        delegate: nil
      }
    }
  end

  def handle_info({_from, {:data, data}}, state) do
    case :erlang.binary_to_term(data) do
      {:response, request_id, payload} ->
        {pid, oustanding} = Map.pop(state.outstanding_requests, request_id)
        GenServer.reply(pid, payload)
        {
          :noreply,
          %AllonetState{state|
            outstanding_requests: oustanding
          }
        }
      {:client_connected, client_id} ->
        send(state.delegate, {:new_client, client_id})
        {
          :noreply,
          state
        }
      {:client_disconnected, client_id} ->
        send(state.delegate, {:lost_client, client_id})
        {
          :noreply,
          state
        }
      {:client_sent, client_id, channel, payload} ->
        parse_payload(client_id, channel, payload, state)
    end
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

  defp parse_payload(client_id, channel, payload, state) do
    # todo: :atoms is dangerous; make sure data conforms to intent/interaction record first
    packet = Jason.decode!(payload, [{:keys, :atoms}])

    # todo: differentiate intents and interactions based on channel!

    msg = case channel do
      @channel_statediffs ->
        :client_intent
      @channel_commands ->
        :client_interaction
      end
    
    send(state.delegate, {msg, client_id, packet})
    {
      :noreply,
      state
    }
  end
end
