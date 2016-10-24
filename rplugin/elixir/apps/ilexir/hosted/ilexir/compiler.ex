defmodule Ilexir.Compiler do
  @moduledoc """
  Compiler.
  """
  alias Ilexir.Compiler.ModuleLocation

  use GenServer

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts ++ [name: __MODULE__])
  end

  def init(_args) do
    {:ok, %{modules: %{}, locations: %{}}}
  end

  def compile_string(string, file \\ "nofile") do
    after_compile_callback_ast = quote do @after_compile unquote(__MODULE__) end

    ast = Code.string_to_quoted!(string)
    GenServer.cast(__MODULE__, {:update_locations, file, ast})

    ast
    |> Macro.postwalk(&inject_after_compile_callback(&1, after_compile_callback_ast))
    |> Code.compile_quoted(file)
  end

  def get_env(param) do
    GenServer.call(__MODULE__, {:get_env, param})
  end

  def set_env(env) do
    GenServer.call(__MODULE__, {:set_env, env})
  end

  def __after_compile__(env, _bytecode) do
    GenServer.call(__MODULE__, {:set_env, env})
  end

  def handle_call({:set_env, env}, _from, state) do
    state = update_env(state, env.module, env)
    {:reply, :ok, state}
  end

  def handle_call({:get_env, {file, line_number}}, _from, state) do
    module = ModuleLocation.find_module(state.locations[file], line_number)
    {:reply, get_env(state, module), state}
  end

  def handle_call({:get_env, module}, _from, state) do
    {:reply, get_env(state, module), state}
  end

  def handle_cast({:update_locations, file, ast}, state) do
    tree = ModuleLocation.to_location_tree(ast)
    state = put_in(state, [:locations, file], tree)
    {:noreply, state}
  end

  defp inject_after_compile_callback({:defmodule, a, [b, [do: {:__block__, opt, inner_items}]]} = _module_ast, callback_ast) do
    new_block = {:__block__, opt, inner_items ++ [[callback_ast]]}
    {:defmodule, a, [b, [do: new_block]]}
  end

  defp inject_after_compile_callback({:defmodule, a, [b, [do: not_a_block]]} = _module_ast, callback_ast) do
    new_block = {:__block__, [], [not_a_block] ++ [callback_ast]}
    {:defmodule, a, [b, [do: new_block]]}
  end

  defp inject_after_compile_callback(block, _callback_ast), do: block

  defp get_env(state, module) do
    get_in(state, [:modules, "#{module}", :env])
  end

  defp update_env(state, _module, env) do
    module_data = get_in(state, [:modules, "#{env.module}"]) || %{env: nil, bindings: []}
    module_data = %{module_data | env: env}
    put_in(state, [:modules, "#{env.module}"], module_data)
  end
end
