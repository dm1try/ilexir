defmodule Ilexir.Plugin do
  use NVim.Plugin
  import NVim.Session

  command ilexir_start_app(path) do
    response_to_vim = case Ilexir.HostAppManager.start_app(path) do
      {:ok, _app} ->
        "application successfuly started!"
      {:error, error} ->
        "problem with running the app: #{inspect error}"
    end

    vim_command "echo '#{response_to_vim}'"
  end

  command ilexir_running_apps do
    apps = Ilexir.HostAppManager.running_apps()

    vim_command "echo '#{inspect apps}'"
  end
end
