defmodule Ilexir.Linter do
  use GenServer
  alias  Ilexir.{QuickFix, HostApp}

  @hosted_path Path.expand("#{__DIR__}/../../hosted/ilexir")

  def start_link(args \\ [], _opts \\ []) do
    {:ok, pid} = result = GenServer.start_link(__MODULE__, args, name: __MODULE__)
    Ilexir.HostAppManager.subscribe_on_app_load(pid)
    result
  end

  def check(file, content, linter, app) do
    GenServer.call(__MODULE__, {:check, file, content, linter, app})
  end

  def handle_call({:check, file, content, linter, app}, _from, state) do
    fix_items = HostApp.call(app, linter, :run, [file, content])

    if Enum.any?(fix_items) do
      QuickFix.update_items(fix_items)
    else
      QuickFix.clear_items()
    end

    {:reply, :ok, state}
  end

  def handle_info({:on_app_load, app}, state) do
    Ilexir.HostApp.load_file(app, "#{__DIR__}/quick_fix/item.ex")
    Ilexir.HostApp.load_file(app, "#{@hosted_path}/linter/dummy.ex")
    Ilexir.HostApp.load_file(app, "#{@hosted_path}/linter/ast.ex")

    {:noreply, state}
  end
end

