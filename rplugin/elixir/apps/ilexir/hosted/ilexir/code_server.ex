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
    table = :ets.new(@cache_name, [:named_table])
    {:ok, table}
  end

  def get_modules do
    GenServer.call(__MODULE__, :get_modules)
  end

  def get_elixir_docs(module, type) do
    GenServer.call(__MODULE__, {:get_elixir_docs, module, type})
  end

  def handle_call(:get_modules, _from, table) do
    all_modules = lookup :all_modules, fn->
      all_modules()
    end
    {:reply, all_modules, table}
  end

  def handle_call({:get_elixir_docs, module, type}, _from, table) do
    all_docs = lookup {:elixir_docs, module}, fn->
      Code.get_docs(module, :all)
    end
    {:reply, all_docs && all_docs[type] || [], table}
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
end
