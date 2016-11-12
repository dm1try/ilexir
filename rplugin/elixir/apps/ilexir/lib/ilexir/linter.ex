defmodule Ilexir.Linter do
  @moduledoc false
  use GenServer
  require Logger

  alias  Ilexir.{QuickFix, HostApp}

  def start_link(args \\ [], _opts \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, %{apps_with_credo_ids: []}}
  end

  def check(file, content, linter_or_opts, app) do
    GenServer.call(__MODULE__, {:check, file, content, linter_or_opts, app})
  end

  def handle_call({:check, file, content, linter, app}, _from, state) when is_atom(linter) do
    run_linter(app, linter, file, content)
    {:reply, :ok, state}
  end

  def handle_call({:check, file, content, opts, app}, _from, state) when is_list(opts) do
    allow_compile? = Keyword.get(opts, :allow_compile, false)

    linters = find_suitable_linters(allow_compile?)
    spawn_link fn->
      Enum.each(linters, &run_linter(app, &1, file, content))
    end

    {:reply, :ok, state}
  end

  def handle_call({:on_app_load, app}, _from, %{apps_with_credo_ids: apps_with_credo_ids} = state) do
    workers = bootstrap_app(app)

    state = if app_has_credo?(app) do
      bootstrap_credo(app)
      ids = [app.id | apps_with_credo_ids]
      %{state | apps_with_credo_ids: ids}
    else
      state
    end

    {:reply, {:ok, workers}, state}
  end

  defp find_suitable_linters(allow_compile?) do
    alias Ilexir.Linter.{Compiler, Ast, Xref}
    if allow_compile?, do: [Compiler, Xref], else: [Ast]
  end

  defp run_linter(app, linter, file, content) do
    case HostApp.call(app, linter, :run, [file, content]) do
      fix_items when is_list(fix_items) ->
        QuickFix.update_items(fix_items, to_string(linter))
      {:error, error} ->
        Logger.error("Problem with running a linter: #{inspect error}")
    end
  end

  defp bootstrap_app(app) do
    HostApp.call(app, Code, :load_file, ["#{__DIR__}/quick_fix/item.ex"])

    HostApp.load_hosted_file(app, "ilexir/linter/ast.ex")
    HostApp.load_hosted_file(app, "ilexir/linter/compiler.ex")
    HostApp.load_hosted_file(app, "ilexir/standard_error_stub.ex")
    HostApp.load_hosted_file(app, "ilexir/linter/xref.ex")

    [Supervisor.Spec.worker(Ilexir.StandardErrorStub,[[],[]])]
  end

  defp app_has_credo?(%{mix_app?: false}), do: false
  defp app_has_credo?(%{mix_app?: true} = app) do
    config = HostApp.call(app, Mix.Project, :config, [])
    Enum.any?(config[:deps], fn(dep)-> elem(dep, 0) == :credo end)
  end

  defp bootstrap_credo(app) do
    HostApp.call(app, Application, :ensure_all_started, [:credo])
    HostApp.load_hosted_file(app, "ilexir/linter/credo.ex")
  end
end

