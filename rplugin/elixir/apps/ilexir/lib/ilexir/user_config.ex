defmodule Ilexir.UserConfig do
  @callback get(String.t, any) :: any
  @callback set(String.t, any) :: :ok | :error
end
