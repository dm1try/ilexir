defmodule Ilexir.ObjectSource do
  @moduledoc """
  Lookups for code "objects" in the elixir code and inspects them.
  """

  alias Ilexir.Code.Server, as: CodeServer
  import Ilexir.ObjectSource.Web

  @type source_object :: {:module, atom} | {:erlang_module, atom} | {:function, atom, atom}

  @spec find_object(String.t(), number, list) :: source_object | nil
  @doc "Finds source object for the current position in line"
  def find_object(line, current_column, opts \\ []) do
    env = Keyword.get(opts, :env)

    tokens = tokens(line)
    tokens |> current_token(current_column) |> process_token(tokens, env)
  end

  @doc "Returns source object path for current position in line"
  def find_source(line, current_column, opts \\ []) do
    case find_object(line, current_column, opts) do
      {type, object} when type in [:module, :erlang_module, :function] ->
        CodeServer.get_source(object)
      _ -> :not_implemented
    end
  end

  @doc "Returns online docs for current position in line"
  def online_docs_url(line, current_column, opts \\ []) do
    case find_object(line, current_column, opts) do
      {type, _} = object when type in [:module, :erlang_module, :function] ->
        {:ok, docs_url(object)}
      _ ->
        {:error, :not_implemented}
    end
  end

  defp tokens(line) do
    line |> tokenized |> Enum.with_index
  end

  defp tokenized(line) do
    case  :elixir_tokenizer.tokenize(to_charlist(line), 0, 0, [check_terminators: false]) do
      {:ok, _, _, tokens} -> tokens
      _ -> []
    end
  end

  defp current_token(tokens, current_column) do
    Enum.find(tokens, fn({token, _index})->
      {_, start_col, end_col} = elem(token, 1)
      start_col <= current_column && current_column < end_col
    end)
  end

  defp process_token({{:atom, _location, mod}, _index}, _tokens, _env), do: {:erlang_module, mod}
  defp process_token({{:aliases, _, aliases}, index}, tokens, env) do
    aliases = prev_aliases(tokens, index) ++ aliases
    mod = aliases |> Module.concat |> resolve_alias(env)

    {:module, mod}
  end

  defp process_token({{identifier, _location, func}, index}, tokens, env)
    when identifier in [:identifier, :paren_identifier] do
    case Enum.at(tokens, index - 1) do
      {{:., _,}, index} ->
        case Enum.at(tokens, index - 1) do
          {{:atom, _location, mod}, _index} ->
            {:function, {mod, func}}
          {{:aliases, _location, aliases}, index} ->
            aliases =  prev_aliases(tokens, index) ++ aliases
            mod = aliases |> Module.concat |> resolve_alias(env)
            {:function, {mod, func}}
            _ -> nil
        end
      _ ->
        if imported = resolve_import(func, env), do: {:function, imported}
    end
  end

  defp process_token(_, _, _), do: nil
  defp prev_aliases(_tokens, index) when index < 2, do: []
  defp prev_aliases(tokens, index) do
    tokens |> Enum.slice(0..index-1) |> Enum.reverse |> fetch_aliases([])
  end

  defp fetch_aliases([{{:., _},_} | rest], res), do: fetch_aliases(rest, res)
  defp fetch_aliases([{{:aliases, _, [aliases]},_} | rest], res), do: fetch_aliases(rest, [aliases|res])
  defp fetch_aliases(_, res), do: res

  defp resolve_alias(mod, nil = _nil), do: mod
  defp resolve_alias(mod, %{aliases: aliases} = _env) do
    Enum.find_value(aliases, &(elem(&1,0) == mod && elem(&1,1))) || mod
  end

  defp resolve_import(_func_name, nil), do: nil
  defp resolve_import(func_name, %{functions: functions} = _env) do
    Enum.find_value functions, fn({mod, functions})->
      Enum.find(functions, &(elem(&1, 0) == func_name)) && {mod, func_name}
    end
  end
end
