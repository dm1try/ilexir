defmodule Ilexir.Plugin do
  use NVim.Plugin
  import NVim.Session

  require Logger

  alias Ilexir.HostAppManager, as: AppManager
  alias Ilexir.Linter

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

  on_event :insert_leave, [pattern: "*.{ex,exs}"], do: lint(Linter.Ast)
  on_event :text_changed, [pattern: "*.{ex,exs}"], do: lint(Linter.Ast)
  on_event :buf_write_post, [pattern: "*.{ex,exs}"], do: lint(Linter.Compiler)

  defp lint(linter_mod) do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, lines} <- nvim_buf_get_lines(buffer, 0, -1, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      content = Enum.join(lines, "\n")
      Linter.check(filename, content, linter_mod, app)
    else
      error ->
        Logger.warn("Unable to lint the buffer: #{inspect error}")
    end
  end
end
