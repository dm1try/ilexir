defmodule Ilexir.Compiler do
  @moduledoc """
  Saves module env and bindings between compilations/evaluations.
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

  def eval_string(string, module_name) do
    GenServer.call(__MODULE__, {:eval_string, string, module_name})
  end

  def eval_string(string, file_name, line_number) do
    GenServer.call(__MODULE__, {:eval_string, string, file_name, line_number})
  end

  def get_env(module) do
    GenServer.call(__MODULE__, {:get_env, module})
  end

  def set_env(env) do
    GenServer.call(__MODULE__, {:set_env, env})
  end

  def __after_compile__(env, _bytecode) do
    GenServer.call(__MODULE__, {:set_env, env})
  end

  def handle_call({:eval_string, string, module_name}, _from, state) do
    env = get_env(state, module_name)
    bindings = get_bindings(state, module_name)

    {response, new_state} = do_eval(state, string, bindings, env, module_name)

    {:reply, response, new_state}
  end

  def handle_call({:eval_string, string, file_name, line_number}, _from, state) do
    module_name = ModuleLocation.find_module(state.locations[file_name], line_number)

    env = get_env(state, module_name)
    bindings = get_bindings(state, module_name)

    {response, new_state} = do_eval(state, string, bindings, env, module_name)

    {:reply, response, new_state}
  end

  def handle_call({:set_env, env}, _from, state) do
    state = update_env(state, env.module, env)
    {:reply, :ok, state}
  end

  def handle_call({:get_env, module}, _from, state) do
    {:reply, get_env(state, module), state}
  end

  def handle_call({:get_bindings, module}, _from, state) do
    {:reply, get_bindings(state, module), state}
  end

  def handle_call({:set_bindings, module, bindings}, _from, state) do
    state = update_bindings(state, module, bindings)
    {:reply, :ok, state}
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

  defp do_eval(state, _string, _bindings, nil = _env, module_name) do
    {{:error, "#{module_name} must be compiled with Ilexir compiler before inline evaluation"}, state}
  end

  defp do_eval(state, string, bindings, env, module_name) do
    try do
      {result, bindings} = Code.eval_string(string, bindings, env)
      new_state = update_bindings(state, module_name, bindings)
      {{:ok, result}, new_state}
    rescue
      error in CompileError ->
        case Regex.named_captures(~r/undefined function (?<var_name>\w+)\/./, error.description) do
          %{"var_name" => var} ->
            {{:undefined, var}, state}
          _ ->
            {{:error, error.description}, state}
        end
      any ->
        {{:error, "#{inspect any}"}, state}
    end
  end

  defp get_env(state, module) do
    get_in(state, [:modules, "#{module}", :env])
  end

  defp update_env(state, _module, env) do
    module_data = get_in(state, [:modules, "#{env.module}"]) || %{env: nil, bindings: []}
    module_data = %{module_data | env: env}
    put_in(state, [:modules, "#{env.module}"], module_data)
  end

  defp get_bindings(state, module) do
    get_in(state, [:modules, "#{module}", :bindings]) || []
  end

  defp update_bindings(state, module, bindings) do
    update_in(state, [:modules, "#{module}", :bindings], &(&1 ++ bindings))
  end
end
