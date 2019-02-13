defmodule AllonetState do
  defstruct udpport: 31337,
    delegate: nil, # pid()
    port: nil, # port()
    next_request_id: 1, # int()
    outstanding_requests: %{} # int() -> pid()
end

defmodule AlloPlaceserv.MmAllonet do
  use GenServer
  require Logger

  def start_link(opts, delegate, udpport) do
    GenServer.start_link(__MODULE__, %AllonetState{
      delegate: delegate,
      udpport: udpport
    }, opts)
  end

  def init(initial_state) do
    port = Port.open({:spawn, "priv/AllonetPort"}, [
      {:packet, 2},
      :binary,
      :nouse_stdio
    ])

    {:ok, %AllonetState{initial_state|
      port: port
    }}
  end

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
    receive do
      {_port, :closed} ->
        :ok
    end
    { :reply,
      :ok,
      state
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
      {:client_sent, client_id, payload} ->
        parse_payload(client_id, payload, state)
    end
  end

  defp parse_payload(client_id, payload, state) do
    # todo: :atoms is dangerous; make sure data conforms to intent record first
    intent_packet = Jason.decode!(payload, [{:keys, :atoms}])

    send(state.delegate, {:client_intent, client_id, intent_packet})
    {
      :noreply,
      state
    }
  end
end
