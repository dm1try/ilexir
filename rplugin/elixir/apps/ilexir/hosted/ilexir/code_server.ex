defmodule Ilexir.CodeServer do
  @moduledoc """
  Wrapes elixir/erlang sources and returns meta information about code.
  """

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

  def handle_call(:get_modules, _from, state) do
    all_modules = lookup :all_modules, fn->
      all_modules()
    end

    live_modules = Map.keys(state.modules)

    {:reply, live_modules ++ all_modules, state}
  end

  def handle_call({:get_elixir_docs, module, type}, _from, state) do
    mod = Enum.find_value state.modules, fn({k, v}) ->
      module == k && v
    end

    docs = if mod do
      code = elem(mod, 1)
      do_get_docs(code, type)
    else
      all_docs = lookup {:elixir_docs, module}, fn->
        Code.get_docs(module, :all)
      end

      all_docs && all_docs[type]
    end

    {:reply, docs || [], state}
  end

  def handle_call({:add_module, {module_name, _obj_code, _file_path} = module_info}, _from, state) do
    new_state = put_in(state, [:modules, module_name], module_info)
    {:reply, :ok, new_state}
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

  defp all_modules do
    modules = Enum.map(:code.all_loaded(), &(elem(&1, 0)))
    Enum.sort(modules ++ get_modules_from_applications(), &(&1 > &2))
  end

  defp get_modules_from_applications do
    for [app] <- loaded_applications(),
        {:ok, modules} = :application.get_key(app, :modules),
        module <- modules do module end
  end

  # Extracted from here https://github.com/elixir-lang/elixir/blob/64ee036509c34e097017e89fc0af3818110043d3/lib/iex/lib/iex/autocomplete.ex#L236
  # See the related comment for more info.
  defp loaded_applications do
    :ets.match(:ac_tab, {{:loaded, :"$1"}, :_})
  end


  # see https://github.com/elixir-lang/elixir/blob/c2fd08e20d88ce7c42e9669dbfc2907ae5a5ae97/lib/elixir/lib/code.ex#L630
  @docs_chunk 'ExDc'

  defp do_get_docs(obj_code, kind) do
    case :beam_lib.chunks(obj_code, [@docs_chunk]) do
      {:ok, {_module, [{@docs_chunk, bin}]}} ->
        lookup_docs(:erlang.binary_to_term(bin), kind)

      {:error, :beam_lib, {:missing_chunk, _, @docs_chunk}} -> nil
    end
  end

  defp lookup_docs({:elixir_docs_v1, docs}, kind),
    do: do_lookup_docs(docs, kind)

  # unsupported chunk version
  defp lookup_docs(_, _), do: nil

  defp do_lookup_docs(docs, :all), do: docs
  defp do_lookup_docs(docs, kind),
    do: Keyword.get(docs, kind)
end
