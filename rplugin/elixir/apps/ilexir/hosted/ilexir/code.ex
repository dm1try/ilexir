defmodule Ilexir.Code do
  @doc "Returns elixir docs."
  def get_elixir_docs(module, type \\ :all)

  def get_elixir_docs(obj_code, type) when is_binary(obj_code) do
    do_get_docs(obj_code, type) || []
  end

  def get_elixir_docs(module, type) when is_atom(module) do
    Code.get_docs(module, type) || []
  end

  @doc "Returns all available modules founded in running application."
  def all_modules do
    modules = Enum.map(:code.all_loaded(), &(elem(&1, 0)))
    modules ++ get_modules_from_applications()
  end

  defp get_modules_from_applications do
    for [app] <- loaded_applications(),
        {:ok, modules} = :application.get_key(app, :modules),
        module <- modules do module end
  end

  # Extracted from here
  # https://github.com/elixir-lang/elixir/blob/64ee036509c34e097017e89fc0af3818110043d3/lib/iex/lib/iex/autocomplete.ex#L236
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

  defp lookup_docs({:elixir_docs_v1, docs}, kind), do: do_lookup_docs(docs, kind)
  defp lookup_docs(_, _), do: nil

  defp do_lookup_docs(docs, :all), do: docs
  defp do_lookup_docs(docs, kind), do: Keyword.get(docs, kind)
end
