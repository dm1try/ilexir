defmodule Ilexir.UserConfig.Test do
  @behaviour Ilexir.UserConfig

  def get(_name, default \\ nil) do
    default
  end

  def set(_name, _value) do
    :ok
  end
end
