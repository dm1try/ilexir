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
    {:ok, %{timer_ref: nil, current_app_id: nil}}
  end

  # Host manager interface

  command ilexir_start_app(params),
    complete: :file
  do
    [path | args] = params
    app_id = start_app(path, args)
    state = %{state | current_app_id: app_id}
  end

  command ilexir_start_in_working_dir(params) do
    app_id = case nvim_call_function("getcwd", []) do
      {:ok, working_dir} ->
        start_app(working_dir, params)
      _ ->
        warning_with_echo("Unable to get 'current_dir'")
        nil
    end

    state = %{state | current_app_id: app_id}
  end

  command ilexir_running_apps do
    apps = AppManager.running_apps()
    vim_command "echo '#{inspect apps}'"
  end

  command ilexir_stop_app do
    with {:ok, app} <- AppManager.get_app(state.current_app_id) do
      AppManager.stop_app(app)
      echo ~s[Application "#{app.name}(#{app.env})" going to stop.]
    else
      error ->
        warning_with_echo("Unable to stop the app: #{inspect error}")
    end
  end

  command ilexir_open_iex do
    with {:ok, app} <- AppManager.get_app(state.current_app_id) do

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
    with {:ok, app} <- AppManager.get_app(state.current_app_id) do
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

  on_event :buf_enter, [pattern: "*.{ex,exs}"] do
    state = with {:ok, buffer} <- nvim_get_current_buf(),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, %{id: app_id}} <- AppManager.lookup(filename) do

      %{state | current_app_id: app_id}
    else
      _ -> state
    end
  end

  @delay_time 300 # ms
  defp delayed_lint(timer_ref) do
    :timer.cancel(timer_ref)
    {:ok, timer_ref} = :timer.apply_after(@delay_time, __MODULE__, :lint, [[allow_compile: autocompile_enabled?]])
    timer_ref
  end

  # GoToDefinition interface

  command ilexir_go_to_def,
    pre_evaluate: %{
      "col('.') - 1" => current_column_number,
      "line('.') - 1" => current_line_number
    }
  do
    with {:ok, buffer} <- nvim_get_current_buf(),
         {:ok, line} <- nvim_get_current_line(),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.get_app(state.current_app_id) do

       opts =
         if env = current_env(app, filename, current_line_number) do
           [env: env]
         else
           flash_echo "Current enviroment is missed."
           []
         end

       case App.call(app, Ilexir.ObjectSource, :find_source, [line, current_column_number, opts]) do
         {path, line} ->
           case nvim_command "e #{path} | :#{line}" do
             {:error, error} -> echo "Unable go to path: #{path}, detail: #{inspect error}"
             _ -> :ok
           end
         res -> echo "Definition is not found. Details: #{inspect res}"
       end
    else
      error -> warning_with_echo("Unable to evaluate lines: #{inspect error}")
    end
  end
  # Autocomplete interface

  function ilexir_complete(find_start, base),
    pre_evaluate: %{
      "col('.') - 1" => current_column_number,
      "line('.') - 1" => current_line_number,
      "getline('.')" => current_line
    }
    do
      with {:ok, buffer} <- vim_get_current_buffer,
      {:ok, filename} <- nvim_buf_get_name(buffer),
      {:ok, app} <- AppManager.get_app(state.current_app_id) do

        if find_start in [1, "1"] do
          App.call(app, Autocomplete, :find_complete_position, [current_line, current_column_number])
        else
          expand_on_host(app, current_line, current_column_number, base, {filename, current_line_number})
        end
      else
        error ->
          Logger.warn("Unable to complete: #{inspect error}")
          -1
      end
    end

  defp expand_on_host(app, current_line, column_number, base, {filename, line_number}) do
    complete_opts =
      if env = current_env(app, filename, line_number) do
        [env: env]
      else
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
  on_event :buf_read_post, pattern: "*.{ex,exs}" do
    nvim_command "set omnifunc=IlexirComplete"
    Ilexir.QuickFix.clear_items()
  end

  defp start_app(path, command_params) do
    {args, _, _} = OptionParser.parse(command_params)
    {:ok, current_dir} = nvim_call_function("getcwd", [])
    path = Path.expand(path, current_dir)

    case AppManager.start_app(path, args ++ [callback: &start_callback/1]) do
      {:ok, %{name: name, env: env, id: id}} ->
        echo ~s[Application "#{name}(#{env})" is loading...]
        id
      {:error, error} ->
        echo "Problem with running the app: #{inspect error}"
        nil
    end
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
      if env = current_env(app, filename, line) do
        [env: env]
      else
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

  defp current_env(app, filename, line) do
    with module when is_atom(module) <- App.call(app, Ilexir.ModuleLocation.Server, :get_module, [filename, line]) do
      App.call(app, Ilexir.Compiler, :get_env, [module])
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
