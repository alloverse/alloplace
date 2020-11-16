defmodule PlaceStoreDaemon do
  use GenServer
  require Logger

  ### Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, {}, opts)
  end

  def init(_) do
    {:ok, Daemon.setup("priv/AlloStatePort")}
  end

  # ... + the public methods in PlaceStore.ex

  ### Internals

  def handle_call(:stop, _from, state) do
    :ok = Daemon.stop(state)
    { :reply,
      :ok,
      state
    }
  end

  def handle_call(ccall, from, state) do
    cmd = elem(ccall, 0)
    args = case ccall do
      {:add_entity, entity} -> with {:ok, json} <- Jason.encode(entity), do: {json}
      {:update_entity, eid, comps, rmcomps} -> with(
        {:ok, cjson} <- Jason.encode(comps),
        {:ok, rmjson} <- Jason.encode(rmcomps),
        do: {eid, cjson, rmjson})
      {:simulate, intents} -> with {:ok, json} <- Poison.encode(intents), do: {json}
      _ -> Tuple.delete_at(ccall, 0)
    end
    {:ok, dstate} = Daemon.call_to_c(cmd, args, from, state)
    { :noreply,
      dstate
    }
  end

  def handle_cast(ccall, state) do
    cmd = elem(ccall, 0)
    args = Tuple.delete_at(ccall, 0)
    {:ok, dstate} = Daemon.call_to_c(cmd, args, state)
    { :noreply,
      dstate
    }
  end

  def handle_info({_from, {:data, data}}, state) do
    {:ok, dstate} = Daemon.handle_call_from_c(data, state)
    {
      :noreply,
      dstate
    }
  end

  # why is :EXIT callled but not this?
  def handle_info({_port, {:exit_status, status}}, state) do
    raise("AlloStatePort died unexpectedly: #{status}")
    {
      :noreply,
      state
    }
  end

  def handle_info({:EXIT, _port, mode}, state) do
    raise("AlloStatePort died unexpectedly: #{mode}")
    {
      :noreply,
      state
    }
  end

end
