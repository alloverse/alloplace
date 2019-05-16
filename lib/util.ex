defmodule Util do
  def generate_id() do
    to_string(Enum.take_random(?a..?z, 10))
  end
end
