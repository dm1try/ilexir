defmodule Ilexir.HostAppManager do
  @moduledoc """
  Responsible for management of hosted applications.

  It starts/stops/restarts hosted nodes and monitor them.
  It bootsraps nodes with hosted code of other system components.
  """
  use GenServer
  alias Ilexir.HostApp, as: App

  @runner Application.get_env(:ilexir, :host_app_runner) || Ilexir.HostApp.NvimTerminalRunner
  @default_runner_opts [nvim_session: NVim.Session]

  require Logger

  @fallback_failure_count 30
  @fallback_timeout 400

  def start_link(args \\ [], _opts \\ []) do
    GenServer.start_link(__MODULE__, args, [name: __MODULE__])
  end

  def init(args) do
    random_string = "#{Enum.shuffle(97..112)}"
    remote_name = :"ilexir_host_#{random_string}"

    Node.start(remote_name, :shortnames)
    subscribers = Keyword.get(args, :subscribers, [])
    {:ok, %{remote_name: remote_name, subscribers: subscribers, apps: %{}, last_app_id: 0}}
  end

  def start_app(path, args \\ []) do
    GenServer.call(__MODULE__, {:start_app, path, args})
  end

  def stop_app(app_or_name, opts \\ []) do
    GenServer.call(__MODULE__, {:stop_app, app_or_name, opts})
  end

  def lookup(file_path) do
    GenServer.call(__MODULE__, {:lookup, file_path})
  end

  def running_apps do
    GenServer.call(__MODULE__, :running_apps)
  end

  def subscribe_on_app_load(subscriber) do
    GenServer.cast(__MODULE__, {:subscribe_on_app_load, subscriber})
  end

  def handle_call({:lookup, file_path}, _from, state) do
    result = case App.lookup(file_path, Map.values(state.apps)) do
      %{status: :running} = app -> {:ok, app}
      _ -> {:error, :no_running_apps}
    end

    {:reply, result, state}
  end

  def handle_call({:start_app, path, args}, _from, state) do
    app = App.build(path, args)

    {response, state} = if Enum.any?(state.apps, &(elem(&1, 1).remote_name == app.remote_name)) do
      { {:error, :already_started}, state}
    else
      app_id = state.last_app_id + 1
      app = %{app | id: app_id}

      app = if callback = Keyword.get(args, :callback) do
        new_meta = Map.put(app.meta, :caller_callback, callback)
        %{app | meta: new_meta}
      else
        app
      end

      app = case @runner.start_app(app, @default_runner_opts ++ args) do
        {:ok, app} ->
          :timer.send_after @fallback_timeout, {:check_loading_status, app_id, @fallback_failure_count}
          %{app | status: :loading}
        {:error, app} ->
          %{app | status: :failed_to_run}
      end

      state = put_in(state, [:apps, app_id], app)
      { {:ok, app}, %{state | last_app_id: app_id} }
    end

    {:reply, response, state}
  end

  def handle_call(:running_apps, _from, state) do
    {:reply, Map.values(state.apps), state}
  end

  def handle_call({:stop_app, app_id, opts}, _from, state) when is_number(app_id) do
    case Enum.find(state.apps, fn({id, _app})-> id == app_id  end) do
      nil -> {:reply, nil, state}
      {_app_id, app} ->
        stop_hosted_app(app, opts)
        {:reply, app, state}
    end
  end

  def handle_call({:stop_app, app, opts}, _from, state) when is_map(app) do
    stop_hosted_app(app, opts)
    {:reply, {:ok, app}, state}
  end

  defp stop_hosted_app(app, opts) do
    App.call(app, :init, :stop, [])
    @runner.on_exit(app, opts ++ @default_runner_opts)
  end

  def handle_cast({:subscribe_on_app_load, subscriber}, state) do
    state = %{state | subscribers: state.subscribers ++ [subscriber]}
    {:noreply, state}
  end

  def handle_info({:check_loading_status, app_id, failure_count}, state) do
    state = case get_in(state, [:apps, app_id]) do
      %{status: :loading} = app ->
        if started?(app) do
          Node.monitor(app.remote_name, true)
          bootstrap_host(app, state.subscribers)

          app = %{app | status: :running}
          notify_caller(app)
          put_in(state, [:apps, app_id], app)
        else
          if failure_count > 0 do
            :timer.send_after @fallback_timeout, {:check_loading_status, app_id, failure_count - 1}
            state
          else
            app = %{app | status: :timeout}
            notify_caller(app)
            {_, state} = pop_in(state, [:apps, app_id])
            state
          end
        end
      _ ->
        state
    end

    {:noreply, state}
  end

  def handle_info({message, remote_name}, state) when message in [:node_down, :nodedown] do
    app_id = Enum.find_value state.apps, fn({app_id, app})->
      remote_name == app.remote_name && app_id
    end

    state = if app_id do
      {app, state} = pop_in(state, [:apps, app_id])
      app = %{app | status: :down}
      notify_caller(app)

      state
    else
      state
    end

    {:noreply, state}
  end

  defp notify_caller(%{meta: %{caller_callback: callback}} = app) when is_function(callback) do
    spawn fn-> callback.(app) end
  end

  defp notify_caller(_app), do: nil

  defp started?(%{mix_app?: false} = app) do
    node_running?(app) && code_server_running?(app)
  end

  defp started?(%{mix_app?: true} = app) do
    node_running?(app) && app_loaded?(app)
  end

  defp code_server_running?(app) do
    is_pid(App.call(app, Process, :whereis, [:elixir_code_server]))
  end

  defp app_loaded?(app) do
    case App.call(app, :application, :loaded_applications, []) do
      apps when is_list(apps) ->
        Enum.any?(apps, fn({app_name, _, _})-> app_name == String.to_atom(app.name) end)
      _ ->
        Logger.info "#{inspect app.name} is not loaded"
        false
    end
  end

  defp node_running?(app), do: Node.ping(app.remote_name) == :pong

  defp bootstrap_host(app, subscribers) do
    {:ok, core_workers} = bootstrap_core(app)

    subscriber_workers = Enum.flat_map(subscribers, fn(subscriber)->
      case GenServer.call(subscriber, {:on_app_load, app}) do
        {:ok, children} when is_list(children) -> children
        error ->
          Logger.error "Component return wrong response on bootstraping the host: #{inspect error}"
          []
      end
    end)

    bootsrap_test_env(app)

    case App.block_call(app, Supervisor, :start_link, [subscriber_workers ++ core_workers, [strategy: :one_for_one]]) do
      {:ok, _supervisor} -> :ok
      error -> Logger.error "Problem with starting hosted supervision tree: #{inspect error}"
    end
  end

  defp bootsrap_test_env(%{env: "test", mix_app?: true, path: path} = app) do
    # too naive atm
    # TODO: incapsulate the logic in separate module
    with true <- File.dir?("#{path}/test"),
         :ok <- App.call(app, Application, :load, [:ex_unit]) do
      App.call(app, ExUnit, :start, [])
    end

    with true <- File.dir?("#{path}/spec"),
         :ok <- App.call(app, Application, :load, [:espec]) do
      App.call(app, ESpec, :start, [])
    end
  end

  defp bootsrap_test_env(_app), do: nil

  defp bootstrap_core(app) do
    import Supervisor.Spec

    with [_loaded] <- App.load_hosted_file(app, "ilexir/module_location.ex"),
         [_loaded] <- App.load_hosted_file(app, "ilexir/module_location/server.ex"),
         [_loaded] <- App.load_hosted_file(app, "ilexir/compiler.ex"),
         [_loaded|_] <- App.load_hosted_file(app, "ilexir/code_server.ex"),
         [_loaded|_] <- App.load_hosted_file(app, "ilexir/autocomplete.ex"),
         [_loaded|_] <- App.load_hosted_file(app, "ilexir/evaluator.ex") do

           specs = [
             worker(Ilexir.CodeServer, [[],[]]),
             worker(Ilexir.ModuleLocation.Server, [[],[]]),
             worker(Ilexir.Compiler, [[subscribers: %{
                    on_ast_processing: [Ilexir.ModuleLocation.Server],
                    after_compile: [Ilexir.CodeServer]
                  }],[]]),
                worker(Ilexir.Evaluator, [[],[]]),
              ]

      {:ok, specs}
    else
      error -> Logger.error "problem with bootstrapping core components: #{inspect error}"
    end
  end
end
