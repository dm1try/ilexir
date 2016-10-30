defmodule Ilexir.Plugin do
  @moduledoc """
  The "controller" module which contains all available Ilexir commands/functions
  that you can use from neovim.
  """
  use NVim.Plugin
  import NVim.Session
  require Logger

  alias Ilexir.HostAppManager, as: AppManager
  alias Ilexir.HostApp, as: App
  alias Ilexir.Linter
  alias Ilexir.Autocomplete.OmniFunc, as: Autocomplete

  def init(_args) do
    {:ok, %{timer_ref: nil}}
  end

  # Host manager interface

  command ilexir_start_app(params),
    complete: :file
  do
    [path | args] = params
    start_app(path, args)
  end

  command ilexir_start_in_working_dir(params) do
    case nvim_call_function("getcwd", []) do
      {:ok, working_dir} ->
        start_app(working_dir, params)
      _ ->
        warning_with_echo("Unable to get 'current_dir'")
    end
  end

  command ilexir_running_apps do
    apps = AppManager.running_apps()
    vim_command "echo '#{inspect apps}'"
  end

  command ilexir_stop_app do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      AppManager.stop_app(app)
      echo ~s[Application "#{app.name}(#{app.env})" going to stop.]
    else
      error ->
        warning_with_echo("Unable to stop the app: #{inspect error}")
    end
  end

  command ilexir_open_iex do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

    {:ok, wins} = nvim_list_wins()

    app_win = Enum.find_value(wins, fn(win)->
      case  nvim_win_get_var(win, "ilexir_app") do
        {:ok, ilexir_remote_name} ->
          ilexir_remote_name == to_string(app.remote_name) && win
         _ ->
           nil
      end
    end)

    open_command = "res 8| set wfh | terminal iex --sname #{app.name}_#{app.env}_iex --remsh #{app.remote_name}"

    if app_win do
      nvim_set_current_win app_win
      nvim_command "vsplit | #{open_command}"
    else
      nvim_command "bot new | #{open_command}"
    end
    else
      error ->
        warning_with_echo("Unable to open IEx: #{inspect error}")
    end
  end

  function ilexir_get_current_app() do
    with {:ok, buffer} <- vim_get_current_buffer,
    {:ok, filename} <- nvim_buf_get_name(buffer),
    {:ok, app} <- AppManager.lookup(filename) do
      Map.take(app, [:id, :name, :env, :path, :remote_name])
    else
      _ -> -1
    end
  end

  # Compiler interface

  command ilexir_compile do
     with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, lines} <- nvim_buf_get_lines(buffer, 0, -1, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

       content = Enum.join(lines, "\n")
       case App.call(app, Ilexir.Compiler, :compile_string, [content, filename]) do
          {:error, error} ->
            echo "Compile error: #{inspect error}"
          _ ->
            echo "Compiled."
       end
    else
      error ->
        warning_with_echo("Unable to compile the file: #{inspect error}")
    end
  end

  # Evaluator

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

  command ilexir_eval_clear_bindings do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

       case App.call(app, Ilexir.Evaluator, :set_bindings, [[]]) do
         [] -> echo "Cleared."
         _ -> echo "Something was going wrong."
       end
    else
      error ->
        warning_with_echo("Unable to clear bindings: #{inspect error}")
    end
  end

  # Linter interface

  command ilexir_lint(params) do
    name = String.capitalize(Enum.at(params, 0))
    linter_mod = Module.concat(Linter, name)
    lint(linter_mod)
  end

  on_event :text_changed, [pattern: "*.{ex,exs}"] do
    state = %{state | timer_ref: delayed_lint(state.timer_ref)}
  end

  on_event :insert_leave, [pattern: "*.{ex,exs}"] do
    state = %{state | timer_ref: delayed_lint(state.timer_ref)}
  end

  on_event :buf_write_post, [pattern: "*.{ex,exs}"] do
    state = %{state | timer_ref: delayed_lint(state.timer_ref)}
  end

  on_event :cursor_hold_i, [pattern: "*.{ex,exs}"] do
    state = %{state | timer_ref: delayed_lint(state.timer_ref)}
  end

  @delay_time 300 # ms
  defp delayed_lint(timer_ref) do
    :timer.cancel(timer_ref)
    {:ok, timer_ref} = :timer.apply_after(@delay_time, __MODULE__, :lint, [[allow_compile: autocompile_enabled?]])
    timer_ref
  end

  # Autocomplete interface

  function ilexir_complete(find_start, base),
    pre_evaluate: %{
      "col('.') - 1" => current_column_number,
      "line('.') - 1" => current_line_number,
      "getline('.')" => current_line
    }
  do
    if find_start in [1, "1"] do
      find_start_position(current_line, current_column_number)
    else
      do_complete(base, current_line, current_column_number, current_line_number)
    end
  end

  defp find_start_position(current_line, current_column_number) do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      App.call(app, Autocomplete, :find_complete_position, [current_line, current_column_number])
    else
      _ -> -1
    end
  end

  defp do_complete(base, current_line, column_number, line_number) do
    with {:ok, buffer} <- vim_get_current_buffer,
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

    expand_on_host(app, current_line, column_number, base, {filename, line_number})
    else
      error ->
        Logger.warn("Unable to complete: #{inspect error}")
        -1
    end
  end

  defp expand_on_host(app, current_line, column_number, base, {filename, line_number}) do
    complete_opts =
      with module when is_atom(module) <- App.call(app, Ilexir.ModuleLocation.Server, :get_module, [filename, line_number]),
      env when is_map(env) <- App.call(app, Ilexir.Compiler, :get_env, [module]) do
        [env: env]
      else
        _ ->
          flash_echo "Results for current enviroment are missed(seems like the current file is not compiled by Ilexir)."
          []
      end

    items = App.call(app, Autocomplete, :expand, [current_line, column_number, base, complete_opts])

    Enum.map items, fn(%{text: text, abbr: abbr, type: type, short_desc: short_desc})->
      %{"word"=>text, "abbr"=> abbr, "kind" => type, "menu" => short_desc}
    end
  end

  # First assumption use FileType event for this.
  # TODO: check why FileType event does not triggered for openning the file directly:
  # $ nvim some_file.ex
  on_event :buf_enter, pattern: "*.{ex,exs}" do
    nvim_command "set omnifunc=IlexirComplete"
  end

  defp start_app(path, command_params) do
    {args, _, _} = OptionParser.parse(command_params)
    {:ok, current_dir} = nvim_call_function("getcwd", [])
    path = Path.expand(path, current_dir)
    case AppManager.start_app(path, args ++ [callback: &start_callback/1]) do
      {:ok, app} ->
        ~s[Application "#{app.name}(#{app.env})" is loading...]
      {:error, error} ->
        "Problem with running the app: #{inspect error}"
    end |> echo
  end

  def start_callback(%{status: status, name: name, env: env} = _app) do
    prefix = ~s[Application "#{name}(#{env})" ]

    postfix = case status do
      :running -> "ready!"
      :timeout -> "unable to start!"
      :down -> "was shut down!"
      _ -> "changed status to #{status}!"
    end

    echo (prefix <> postfix)
  end

  def lint(linter_mod) do
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

  defp autocompile_enabled? do
    nvim_get_var("ilexir_autocompile") != {:ok, 0}
  end

  defp evaluate_with_undefined(app, content, filename, line) do
    eval_opts =
      with module when is_atom(module) <- App.call(app, Ilexir.ModuleLocation.Server, :get_module, [filename, line]),
      env when is_map(env) <- App.call(app, Ilexir.Compiler, :get_env, [module]) do
        [env: env]
      else
        _ ->
          flash_echo "Current enviroment is missed(seems like the current file is not compiled by Ilexir)."
          []
      end

    case App.call(app, Ilexir.Evaluator, :eval_string, [content, eval_opts]) do
      {:ok, result} -> echo_i(result)
      {:undefined, var} ->
        {:ok, result} = nvim_call_function("input", ["Please provide '#{var}' to continue: "])
        App.call(app, Ilexir.Evaluator, :eval_string, ["#{var} = #{result}", eval_opts])
        evaluate_with_undefined(app, content, filename, line)
      {:error, error} -> echo_i(error)
    end
  end

  defp warning_with_echo(message) do
    Logger.warn(message)
    echo(message)
  end

  @highlight_group "Special"

  def echo(param) do
    vim_command ~s(echohl #{@highlight_group} | echo '#{param}' | echohl")
  end

  def echo_i(param) do
    param |> inspect(pretty: true) |> echo
  end

  defp flash_echo(param, delay \\ 2000) do
    spawn_link fn->
      :timer.sleep delay
      echo(param)
    end
  end
end
