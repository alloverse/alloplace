defmodule AlloPlaceserv.MmAllonet do
  require Logger

  @spec start(integer(), pid()) :: {:ok, pid()}
  def start(udpport, parent) do
    {:ok, spawn_link(fn -> init(udpport, parent) end)}
  end

  def foo(mm, num) do
    send(mm, {:call, self(), {:foo, num}})
    receive do
      {:reply, reply} ->
        reply
    end
  end

  def stop(mm) do
    send(mm, :stop)
  end

  def init(udpport, parent) do
    port = Port.open({:spawn, "priv/AllonetPort"}, [{:packet, 2}, :binary])
    loop(port, parent)
  end

  def loop(port, parent) do
    receive do
      {:call, caller, msg} ->
        send(port, {self(), {:command, :erlang.term_to_binary(msg)}})
        receive do
          {port, {:data, data}} ->
            send(caller, {:reply, :erlang.binary_to_term(data)})
        end
        loop(port, parent)
      :stop ->
        send(port, {self(), :close})
        receive do
          {port, :closed} ->
            :ok
        end
    end
  end
end
