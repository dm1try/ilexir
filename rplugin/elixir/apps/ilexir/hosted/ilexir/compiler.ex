defmodule Ilexir.Compiler do
  @moduledoc """
  Compiles files and saves their env values.
  Notifies subscribers on ast processing/after compilation.
  """
  use GenServer

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts ++ [name: __MODULE__])
  end

  def init(args) do
    subscribers = Keyword.get(args, :subscribers, %{})
    {:ok, %{modules: %{}, subscribers: subscribers}}
  end

  def compile_string(string, file \\ "nofile") do
    GenServer.call(__MODULE__, {:compile_string, string, file})
  end

  def get_env(param) do
    GenServer.call(__MODULE__, {:get_env, param})
  end

  def set_env(env) do
    GenServer.call(__MODULE__, {:set_env, env})
  end

  def __after_compile__(env, bytecode) do
    GenServer.call(__MODULE__, {:after_compile, {env, bytecode}})
  end

  def __on_definition__(env, kind, name, args, guards, body) do
    GenServer.call(__MODULE__, {:on_definition, {env, kind, name, args, guards, body}})
  end

  def handle_call({:set_env, env}, _from, state) do
    state = update_env(state, env.module, env)
    {:reply, :ok, state}
  end

  def handle_call({:after_compile, {env, _bytecode} = after_compile_data}, _from, %{subscribers: subscribers} = state) do
    state = update_env(state, env.module, env)

    Enum.each subscribers[:after_compile] || [], fn(subcriber)->
      spawn_link fn-> send subcriber, {:after_compile, after_compile_data} end
    end

    {:reply, :ok, state}
  end

  def handle_call({:on_definition, def_data}, _from, %{subscribers: subscribers} = state) do
    Enum.each subscribers[:on_definition] || [], fn(subcriber)->
      spawn_link fn-> send subcriber, {:on_definition, def_data} end
    end

    {:reply, :ok, state}
  end

  def handle_call({:get_env, module}, _from, state) do
    {:reply, get_env(state, module), state}
  end

  def handle_call({:compile_string, string, file}, from, %{subscribers: subscribers} = state) do
    ast = try do
      Code.string_to_quoted!(string)
    rescue
      error -> GenServer.reply(from, {:error, error})
    end

    Enum.each subscribers[:on_ast_processing] || [], fn(subcriber)->
      spawn_link fn-> send subcriber, {:on_ast_processing, {file, ast}} end
    end

    callbacks_ast = quote do
      @after_compile unquote(__MODULE__)
      @on_definition unquote(__MODULE__)
    end

    ast = Macro.postwalk(ast, &inject_callback_to_ast(&1, [callbacks_ast]))

    spawn_link fn->
      old_ignore_module_opt = Code.compiler_options[:ignore_module_conflict]
      if !old_ignore_module_opt, do: Code.compiler_options(ignore_module_conflict: true)

      try do
        GenServer.reply(from, Code.compile_quoted(ast, file))
      rescue
        error -> GenServer.reply(from, {:error, error})
      after
        if !old_ignore_module_opt, do: Code.compiler_options(ignore_module_conflict: false)
      end
    end

    {:noreply, state}
  end

  defp inject_callback_to_ast({:defmodule, a, [b, [do: {:__block__, opt, inner_items}]]} = _module_ast, callback_ast) do
    new_block = {:__block__, opt, [[callback_ast]] ++ inner_items }
    {:defmodule, a, [b, [do: new_block]]}
  end

  defp inject_callback_to_ast({:defmodule, a, [b, [do: not_a_block]]} = _module_ast, callback_ast) do
    new_block = {:__block__, [], [callback_ast] ++ [not_a_block] }
    {:defmodule, a, [b, [do: new_block]]}
  end

  defp inject_callback_to_ast(block, _callback_ast), do: block

  defp get_env(state, module) do
    get_in(state, [:modules, "#{module}", :env])
  end

  defp update_env(state, _module, env) do
    module_data = get_in(state, [:modules, "#{env.module}"]) || %{env: nil, bindings: []}
    module_data = %{module_data | env: env}
    put_in(state, [:modules, "#{env.module}"], module_data)
  end
end
