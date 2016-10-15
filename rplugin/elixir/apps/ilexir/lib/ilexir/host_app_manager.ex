defmodule Ilexir.HostAppManager do
  use GenServer

  require Logger

  def start_link(_args \\ [], _opts \\ []) do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def init(_args) do
    random_string = "#{Enum.shuffle(97..112)}"
    remote_name = :"ilexir_host_#{random_string}"

    Node.start(remote_name, :shortnames)

    {:ok, %{remote_name: remote_name, app_paths: [], subscribers: [], running_apps: []}}
  end

  def remote_name do
    GenServer.call(__MODULE__, :remote_name)
  end

  def start_app(path, args \\ []) do
    GenServer.call(__MODULE__, {:start_app, path, args})
  end

  def stop_app(app) do
    GenServer.call(__MODULE__, {:stop_app, app})
  end

  def add_app_path(path, _args \\ []) do
    GenServer.call(__MODULE__, {:add_app_path, path})
  end

  def app_paths do
    GenServer.call(__MODULE__, :app_paths)
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

  def stop_all do
    GenServer.call(__MODULE__, :stop_all)
  end

  def handle_call(:remote_name, _from, state) do
    {:ok, host} = :inet.gethostname

    {:reply, :"#{state.remote_name}@#{host}", state}
  end

  def handle_call({:add_app_path, file_path}, _from, state) do
    state = %{state | app_paths: state.app_paths ++ [file_path]}
    {:reply, :ok, state}
  end

  def handle_call(:app_paths, _from, state) do
    {:reply, state.app_paths, state}
  end

  def handle_call(:stop_all, _from, state) do
    Enum.each state.running_apps, fn(app)->
      Ilexir.HostApp.stop(app)
    end

    state = %{state | running_apps: []}
    {:reply, :ok, state}
  end

  def handle_call({:lookup, file_path}, _from, state) do
    app = Enum.find(state.running_apps, fn(app)-> String.contains?(file_path, app.path) end)

    result = if app do
      {:ok, app}
    else
      {:error, "no running apps for file: #{file_path}"}
    end

    {:reply, result, state}
  end

  def handle_call({:start_app, path, args}, _from, state) do
    {response, state} = case Ilexir.HostApp.start(path, args, nvim_session: NVim.Session) do
      {:ok, app} ->
        state = %{state | running_apps: state.running_apps ++ [app]}
        Enum.each(state.subscribers, fn(subscriber)-> send(subscriber, {:on_app_load, app}) end)
      {{:ok, app}, state}
      error ->
        {error, state}
    end

    {:reply, response, state}
  end

  def handle_call(:running_apps, _from, state) do
    {:reply, state.running_apps, state}
  end

  def handle_call({:stop_app, app}, _from, %{running_apps: running_apps} = state) do
    running_apps = case Ilexir.HostApp.stop(app, nvim_session: NVim.Session) do
      {:ok, app} ->
        Enum.reject(running_apps, &(&1 == app))
      {:error, error} ->
        Logger.warn "problem with stopping the app: #{inspect error}"
        running_apps
    end

    state = %{state | running_apps: running_apps}
    {:reply, :ok, state}
  end

  def handle_cast({:subscribe_on_app_load, subscriber}, state) do
    state = %{state | subscribers: state.subscribers ++ [subscriber]}
    {:noreply, state}
  end
end
