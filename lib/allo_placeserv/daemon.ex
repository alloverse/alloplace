defmodule DaemonState do
  defstruct port: nil, # port()
    name: "",
    next_request_id: 1, # int()
    outstanding_requests: %{} # int() -> pid()
end

defmodule Daemon do
  require Logger

  def setup(path) do
    Process.flag(:trap_exit, true)
    port = Port.open({:spawn, path}, [
      {:packet, 4},
      :binary,
      :nouse_stdio
    ])
    Process.link port

    %DaemonState{
      port: port,
      name: path
    }
  end

  def call_to_c(cmd, args, from, state) do
    rid = state.next_request_id
    msg = {cmd, rid, args}
    binmsg = :erlang.term_to_binary(msg)
    send(state.port, {self(), {:command, binmsg}})
    { :ok,
      %DaemonState{state|
        next_request_id: rid+1,
        outstanding_requests: Map.put(state.outstanding_requests, rid, from)
      }
    }
  end

  def call_to_c(cmd, args, state) do
    msg = {cmd, -1, args}
    binmsg = :erlang.term_to_binary(msg)
    send(state.port, {self(), {:command, binmsg}})
    { :ok,
      state
    }
  end

  def handle_call_from_c(data, state) do
    case :erlang.binary_to_term(data) do
      {:response, request_id, payload} ->
        {pid, oustanding} = Map.pop(state.outstanding_requests, request_id)
        GenServer.reply(pid, payload)
        {
          :ok,
          %DaemonState{state|
            outstanding_requests: oustanding
          }
        }
      other ->
        {other, state}
    end
  end

  def stop(state) do
    send(state.port, {self(), :close})
    :ok = receive do
      {_port, :closed} ->
        :ok
      after 1_000 ->
        :timeout
    end
    :ok
  end
end
