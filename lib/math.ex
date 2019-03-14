defmodule Allomath do
  def g2avec({x, y, z}) do
    %AlloVector{x: x, y: y, z: z}
  end
  def a2gvec(%AlloVector{x: x, y: y, z: z}) do
    Graphmath.Vec3.create(x, y, z)
  end
end
