defmodule Ilexir.ModuleLocation.Server do
  use GenServer

  import Ilexir.ModuleLocation, only: [to_location_tree: 1, find_module: 2]

  def start_link(args \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, opts ++ [name: name])
  end

  def init(args \\ []) do
    {:ok, %{locations: %{}}}
  end

  def get_module(server \\ __MODULE__, filename, line)
  when is_atom(server) or is_pid(server)
  do
    GenServer.call(server, {:get_module, filename, line})
  end

  def handle_call({:get_module, filename, line}, _from, %{locations: locations} = state) do
    {:reply, find_module(locations[filename], line), state}
  end

  def handle_info({:on_ast_processing, {filename, ast}}, state) do
    {:noreply, put_in(state, [:locations, filename], to_location_tree(ast))}
  end
end
