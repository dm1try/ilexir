defmodule Ilexir.HostApp.Runner do
  alias Ilexir.HostApp, as: App

  @doc "Starts the app with specific args."
  @callback start_app(%App{}, list) :: {:ok, %App{}} | {:error, any}

  @doc "Can be used to cleanup some resources."
  @callback on_exit(%App{}, list) :: {:ok, %App{}} | {:error, any}
end
