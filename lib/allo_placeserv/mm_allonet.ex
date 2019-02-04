defmodule AllonetState do
  defstruct udpport: 31337,
    delegate: nil, # pid()
    port: nil, # port()
    next_request_id: 1 # int()
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

  def netsend(this, client_id, channel, payload) do
    GenServer.call(this, {:ccall, :send, {client_id, channel, payload}})
  end
  def stop(this) do
    :ok = GenServer.call(this, {:ccall, :stop, {}})
    GenServer.call(this, :stop)
  end
  def disconnect(this, client_id) do
    GenServer.call(this, {:ccall, :disconnect, {client_id}})
  end

  def handle_call({:ccall, cmd, args}, _from, state) do
    id = state.next_request_id
    msg = {cmd, id, args}
    send(state.port, {self(), {:command, :erlang.term_to_binary(msg)}})
    resp = receive do
      {_port, {:data, data}} ->

    end
    { :reply,
      resp,
      %AllonetState{state|
        next_request_id: id+1
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

  def handle_info({:data, data}, state) do
    {:response, request_id, payload} = :erlang.binary_to_term(data)

    {
      :noreply,
      state
    }
  end
end
