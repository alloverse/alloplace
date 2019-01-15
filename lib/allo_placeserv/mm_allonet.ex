defmodule AllonetState do
  defstruct udpport: 31337,
    delegate: nil, # pid()
    port: nil # port()
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

  def foo(this, num) do
    GenServer.call(this, {:ccall, {:foo, num}})
  end

  def stop(this) do
    GenServer.call(this, :stop)
  end

  def handle_call({:ccall, msg}, _from, state) do
    send(state.port, {self(), {:command, :erlang.term_to_binary(msg)}})
    resp = receive do
      {_port, {:data, data}} ->
        :erlang.binary_to_term(data)
    end
    { :reply,
      resp,
      state
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
end
