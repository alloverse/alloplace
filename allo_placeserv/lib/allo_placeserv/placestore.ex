defmodule AlloPlaceserv.PlaceStore do
  use GenServer
  require Logger
  
  def init(initial_state) do
    {:ok, initial_state}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end
end
