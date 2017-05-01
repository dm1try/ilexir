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
    with {:ok, app} <- lookup_current_app(state) do
      AppManager.stop_app(app)
      echo ~s[Application "#{app.name}(#{app.env})" going to stop.]
    else
      error ->
        warning_with_echo("Unable to stop the app: #{inspect error}")
    end
  end

  command ilexir_open_iex do
    with {:ok, app} <- lookup_current_app(state) do

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
     with {:ok, buffer} <- vim_get_current_buffer(),
         {:ok, lines} <- nvim_buf_get_lines(buffer, 0, -1, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- lookup_current_app(state) do

       content = Enum.join(lines, "\n")
       message = case App.call(app, Ilexir.Compiler, :compile_string, [content, filename]) do
          {:error, error} -> "Compile error: #{inspect error}"
          _ -> "Compiled."
       end

       echo message
    else
      error ->
        warning_with_echo("Unable to compile the file: #{inspect error}")
    end
  end

  # Evaluator

  command ilexir_eval, range: true do
    with {:ok, buffer} <- vim_get_current_buffer(),
         {:ok, lines} <- nvim_buf_get_lines(buffer, range_start - 1, range_end, false),
         {:ok, app} <- lookup_current_app(state) do

       content = Enum.join(lines, "\n")

       eval_opts = lookup_env(app, buffer, range_start) |> build_env_opts
       evaluate_with_undefined(app, content, eval_opts)
    else
      error ->
        warning_with_echo("Unable to evaluate lines: #{inspect error}")
    end
  end

  command ilexir_eval_clear_bindings do
    with {:ok, app} <- lookup_current_app(state) do
       message = case App.call(app, Ilexir.Evaluator, :set_bindings, [[]]) do
         [] -> "Cleared."
         _  -> "Something was going wrong."
       end

       echo message
    else
      error -> warning_with_echo("Unable to clear bindings: #{inspect error}")
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

  on_event :vim_enter do
    with {:ok, 1} <- nvim_get_var("ilexir_autostart_app"),
      {:ok, current_dir} <- nvim_call_function("getcwd", []),
      true <- File.exists?(Path.join(current_dir, "mix.exs")) do

        path = Path.expand(".", current_dir)
        if File.dir?("#{path}/apps") do
          umbrella_apps = Path.wildcard("#{path}/apps/*")

          Enum.each umbrella_apps, fn(app_path) ->
            AppManager.put_autostart_path(app_path, [callback: &handle_app_callback/1])
          end
        else
          AppManager.put_autostart_path(path,[callback: &handle_app_callback/1])
        end

      end
  end


  on_event :buf_add, [pattern: "*.{ex,exs}"] do
    with {:ok, buffer} <- nvim_get_current_buf(),
         {:ok, filename} <- nvim_buf_get_name(buffer) do
      AppManager.try_start(filename)
    end
  end

  @delay_time 300 # ms
  defp delayed_lint(timer_ref) do
    :timer.cancel(timer_ref)
    {:ok, timer_ref} = :timer.apply_after(@delay_time, __MODULE__, :lint, [[allow_compile: autocompile_enabled?()]])
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
         {:ok, app} <- lookup_current_app(state) do

       source_opts = lookup_env(app, buffer, current_line_number) |> build_env_opts

       case App.call(app, Ilexir.ObjectSource, :find_source, [line, current_column_number, source_opts]) do
         {:ok, {path, line}} ->
           case nvim_command "e #{path} | :#{line}" do
             {:error, error} -> echo "Unable go to path: #{path}, detail: #{inspect error}"
             _ -> :ok
           end

         {:error, :not_implemented} -> echo "Source not found."
       end
    else
      error -> warning_with_echo("Unable to evaluate lines: #{inspect error}")
    end
  end

  command ilexir_open_online_doc,
    pre_evaluate: %{
      "col('.') - 1" => current_column_number,
      "line('.') - 1" => current_line_number
    }
  do
    with {:ok, buffer} <- nvim_get_current_buf(),
    {:ok, line} <- nvim_get_current_line(),
    {:ok, app} <- lookup_current_app(state) do

      source_opts = lookup_env(app, buffer, current_line_number) |> build_env_opts

      message =
        with {:ok, url} <- App.call(app, Ilexir.ObjectSource, :online_docs_url, [line, current_column_number, source_opts]),
              :ok <- Ilexir.Utils.Web.open_url(url) do

          "#{url} opened."
        else
          {:error, :not_implemented} -> "Source not found."
          :error -> "Problem with running OS command."
        end

      echo message
    else
      error -> warning_with_echo("Unable to open docs: #{inspect error}")
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
    with {:ok, buffer} <- vim_get_current_buffer(),
         {:ok, app} <- lookup_current_app(state) do

      if find_start in [1, "1"] do
        App.call(app, Autocomplete, :find_complete_position, [current_line, current_column_number])
      else
        complete_opts = lookup_env(app, buffer, current_line_number) |> build_env_opts
        items = App.call(app, Autocomplete, :expand, [current_line, current_column_number, base, complete_opts])

        Enum.map items, fn(%{text: text, abbr: abbr, type: type, short_desc: short_desc})->
          %{"word"=>text, "abbr"=> abbr, "kind" => type, "menu" => short_desc, "dup" => 1}
        end
      end
    else
      error ->
        Logger.warn("Unable to complete: #{inspect error}")
        -1
    end
  end

  # First assumption use FileType event for this.
  # TODO: check why FileType event does not triggered for openning the file directly:
  # $ nvim some_file.ex
  on_event :file_type, pattern: "elixir" do
    nvim_command "set omnifunc=IlexirComplete"
  end

  on_event :buf_read_post, pattern: "*.{ex,exs}" do
    nvim_command "set omnifunc=IlexirComplete"
    Ilexir.QuickFix.clear_items()
  end

  defp start_app(path, command_params) do
    {args, _, _} = OptionParser.parse(command_params)
    {:ok, current_dir} = nvim_call_function("getcwd", [])
    path = Path.expand(path, current_dir)

    case AppManager.start_app(path, args ++ [callback: &handle_app_callback/1]) do
      {:ok, %{name: name, env: env, id: id}} ->
        echo ~s[Application "#{name}(#{env})" is loading...]
        id
      {:error, error} ->
        echo "Problem with running the app: #{inspect error}"
        nil
    end
  end

  defp lookup_current_app(%{current_app_id: nil} = _state) do
    with {:ok, buffer} <- nvim_get_current_buf(),
         {:ok, filename} <- nvim_buf_get_name(buffer) do
      AppManager.lookup(filename)
    end
  end

  defp lookup_current_app(%{current_app_id: app_id} = _state) do
    AppManager.get_app(app_id)
  end

  def handle_app_callback(%{status: status, name: name, env: env} = _app) do
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
    with {:ok, buffer} <- vim_get_current_buffer(),
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

  defp evaluate_with_undefined(app, content, eval_opts) do
    case App.call(app, Ilexir.Evaluator, :eval_string, [content, eval_opts]) do
      {:ok, result} -> echo_i(result)
      {:undefined, var} ->
        case var_from_nvim_input(var) do
          {:ok, result} ->
            App.call(app, Ilexir.Evaluator, :eval_string, ["#{var} = #{result}", eval_opts])
            evaluate_with_undefined(app, content, eval_opts)
          _ -> :ignore
        end
      {:error, error} -> echo_i(error)
    end
  end

  @eval_input_timeout 30_000

  defp var_from_nvim_input(var) do
    MessagePack.RPC.Session.call(
      NVim.Session,
      "nvim_call_function",
      ["input", ["Please provide '#{var}' to continue: "]],
      @eval_input_timeout
    )
  end

  defp build_env_opts(env) when env in [nil, false], do: []
  defp build_env_opts(env) when is_map(env), do: [env: env]

  defp get_env(app, buffer, line) do
    with  {:ok, filename} <- nvim_buf_get_name(buffer),
          module when is_atom(module) <- App.call(app, Ilexir.ModuleLocation.Server, :get_module, [filename, line]) do
      App.call(app, Ilexir.Compiler, :get_env, [module])
    else
      nil
    end
  end

  defp lookup_env(app, buffer, line) do
    case get_env(app, buffer, line) do
      %{__struct__: Macro.Env} = env -> env
      nil -> try_compile_buffer(buffer) && get_env(app, buffer, line)
    end
  end

  defp try_compile_buffer(buffer) do
    if autocompile_enabled?() do
      case compile_buffer(buffer) do
        compiled when is_list(compiled) ->
          Logger.info "Buffer was auto compiled(in memory) by Ilexir."
          true
        error ->
          Logger.info("Auto compilation is failed: #{inspect error}")
          false
      end
    else
      false
    end
  end

  def compile_buffer(buffer) do
    with {:ok, lines} <- nvim_buf_get_lines(buffer, 0, -1, false),
         {:ok, filename} <- nvim_buf_get_name(buffer),
         {:ok, app} <- AppManager.lookup(filename) do

      content = Enum.join(lines, "\n")
      App.call(app, Ilexir.Compiler, :compile_string, [content, filename])
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
end
