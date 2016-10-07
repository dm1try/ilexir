defmodule Ilexir.Plugin do
  use NVim.Plugin
  import NVim.Session

  require Logger

  alias Ilexir.HostAppManager, as: AppManager
  alias Ilexir.HostApp, as: App
  alias Ilexir.Linter

  # Host manager interface
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
    apps = AppManager.running_apps()

    vim_command "echo '#{inspect apps}'"
  end

  # Compiler interface

  command ilexir_compile do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, lines} <- nvim_buf_get_lines(buffer, 0, -1, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      content = Enum.join(lines, "\n")
      App.compile_string(app, content, filename)
    else
      error ->
        warning_with_echo("Unable to compile the file: #{inspect error}")
    end
  end

  command ilexir_eval, range: true do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, lines} <- nvim_buf_get_lines(buffer, range_start - 1, range_end, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      content = Enum.join(lines, "\n")

      evaluate_with_undefined(app, content, filename, range_start)
    else
      error ->
        warning_with_echo("Unable to evaluate lines: #{inspect error}")
    end
  end

  # Linter interface

  command ilexir_lint(linter_name) do
    name = String.capitalize(linter_name)
    linter_mod = Module.concat(Linter, name)
    lint(linter_mod)
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

  defp evaluate_with_undefined(app, content, filename, line) do
    case App.eval_string(app, content, filename, line) do
      {:ok, result} -> echo_i(result)
      {:undefined, var} ->
        {:ok, result} = nvim_call_function("input", ["Please provide '#{var}' to continue: "])
        App.eval_string(app, "#{var} = #{result}", filename, line)
        evaluate_with_undefined(app, content, filename, line)
      {:error, error} -> echo_i(error)
    end
  end

  defp warning_with_echo(message) do
    Logger.warn(message)
    echo(message)
  end

  def echo(param) do
    vim_command "echo '#{param}'"
  end

  def echo_i(param) do
    vim_command "echo '#{inspect param, pretty: true}'"
  end
end
