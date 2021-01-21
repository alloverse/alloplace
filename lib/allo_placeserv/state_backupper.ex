defmodule StateBackupper do
  use GenServer

  def start_link opts do
    GenServer.start_link(__MODULE__, {}, opts)
  end
  def init(initial_state) do
    {:ok, initial_state}
  end


  def get self do
    GenServer.call(self, :get)
  end

  def set self, new_state do
    GenServer.cast(self, {:set, new_state})
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:set, new_state}, _state) do
    {:noreply, new_state}
  end

  def terminate _reason, _state do
    :shutdown
  end
end
