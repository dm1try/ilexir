defmodule Ilexir.Linter do
  use GenServer
  require Logger

  alias  Ilexir.{QuickFix, HostApp}

  def start_link(args \\ [], _opts \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def check(file, content, linter, app) do
    GenServer.call(__MODULE__, {:check, file, content, linter, app})
  end

  def handle_call({:check, file, content, linter, app}, _from, state) do
    case HostApp.call(app, linter, :run, [file, content]) do
      fix_items when is_list(fix_items) ->
       QuickFix.update_items(fix_items, to_string(linter))
      {:error, error} ->
        Logger.error "Problem with running a linter(#{linter}): #{inspect error}"
    end

    {:reply, :ok, state}
  end

  def handle_call({:on_app_load, app}, _from, state) do
    workers = bootstrap_app(app)

    {:reply, {:ok, workers}, state}
  end

  defp bootstrap_app(app) do
    Ilexir.HostApp.call(app, Code, :load_file, ["#{__DIR__}/quick_fix/item.ex"])

    Ilexir.HostApp.load_hosted_file(app, "ilexir/linter/dummy.ex")
    Ilexir.HostApp.load_hosted_file(app, "ilexir/linter/ast.ex")

    Ilexir.HostApp.load_hosted_file(app, "ilexir/linter/compiler.ex")
    Ilexir.HostApp.load_hosted_file(app, "ilexir/standard_error_stub.ex")
    bootstrap_credo(app)

    [Supervisor.Spec.worker(Ilexir.StandardErrorStub,[[],[name: Ilexir.StandardErrorStub]])]
  end

  defp bootstrap_credo(%{mix_app?: true} = app) do
    config = HostApp.call(app, Mix.Project, :config, [])

    if Enum.any?(config[:deps], fn(dep)-> elem(dep, 0) == :credo end) do
      HostApp.call(app, Application, :ensure_all_started, [:credo])
      HostApp.load_hosted_file(app, "ilexir/linter/credo.ex")
    end
  end

  defp bootstrap_credo(_app), do: nil
end

