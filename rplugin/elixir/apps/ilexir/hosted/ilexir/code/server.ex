defmodule Ilexir.Code.Server do
  @moduledoc """
  Wrapes elixir/erlang sources and returns meta information about code.
  """
  alias Ilexir.Code

  use GenServer
  @cache_name :code_server_cache

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts ++ [name: __MODULE__])
  end

  def init(_args) do
    :ets.new(@cache_name, [:named_table])
    {:ok, %{modules: %{}}}
  end

  def get_modules do
    GenServer.call(__MODULE__, :get_modules)
  end

  def get_elixir_docs(module, type) do
    GenServer.call(__MODULE__, {:get_elixir_docs, module, type})
  end

  def add_module(module_info) do
    GenServer.call(__MODULE__, {:add_module, module_info})
  end

  @doc "Returns location for module/function."
  def get_source(object) do
    GenServer.call(__MODULE__, {:get_source, object})
  end

  def handle_call(:get_modules, _from, state) do
    all_modules = lookup :all_modules, fn->
      Code.all_modules() |> Enum.sort(&(&1 > &2))
    end

    live_modules = Map.keys(state.modules)

    {:reply, live_modules ++ all_modules, state}
  end

  def handle_call({:get_elixir_docs, module, type}, _from, state) do
    live_mod_code = Enum.find_value state.modules, fn({k, v}) ->
      module == k && elem(v, 1)
    end

    docs = if live_mod_code do
      Code.get_elixir_docs(live_mod_code, type)
    else
      all_docs = lookup {:elixir_docs, module}, fn->
        Code.get_elixir_docs(module, :all)
      end

      all_docs && all_docs[type]
    end

    {:reply, docs || [], state}
  end

  def handle_call({:add_module, {module_name, _obj_code, _file_path} = module_info}, _from, state) do
    new_state = put_in(state, [:modules, module_name], module_info)
    {:reply, :ok, new_state}
  end

  def handle_call({:get_source, module_name}, _from, %{modules: modules} = state) when is_atom(module_name) do
    result = case Map.get(modules, module_name) do
      {mod, code, file_path} ->
        {file_path, Code.find_source_line({:module, mod}, code)}
      _ ->
        with code <- Code.get_object_code(module_name),
             path <- Code.get_source_path(module_name),
             line <- Code.find_source_line({:module, module_name}, code) do

          {path, line}
        end
    end

    {:reply, result, state}
  end

  def handle_call({:get_source, {module_name, func}}, _from, %{modules: modules} = state) do
    result = case Map.get(modules, module_name) do
      {_mod, code, file_path} ->
        {file_path, Code.find_source_line({:function, func}, code)}
      _ ->
        with code <- Code.get_object_code(module_name),
             path <- Code.get_source_path(module_name),
             line <- Code.find_source_line({:function, func}, code) do

          {path, line}
        end
    end

    {:reply, result, state}
  end

  def handle_info({:after_compile, {env, obj_code}}, state) do
    new_state = put_in(state, [:modules, env.module], {env.module, obj_code, env.file})
    {:noreply, new_state}
  end

  defp lookup(cache_key, missing_callback) do
    case :ets.lookup(@cache_name, cache_key) do
      [{^cache_key, result}] -> result
      [] ->
        result = missing_callback.()
        :ets.insert(@cache_name, {cache_key, result})
        result
    end
  end
end
