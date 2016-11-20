defmodule Ilexir.ObjectSource do
  @moduledoc """
  Lookups for code "objects" in the elixir code and inspects them.
  """

  alias Ilexir.Code.Server, as: CodeServer
  import Ilexir.ObjectSource.Web
  import Ilexir.Code, only: [elixir_module?: 1]

  @type source_function :: {atom, {atom, number}} | {atom, atom}
  @type source_object :: {:module, atom} | {:erlang_module, atom} | {:function, source_function} | {:erlang_function, source_function}
  @supported_types [:module, :function, :erlang_module, :erlang_function]

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
      {type, object} when type in @supported_types ->
        {:ok, CodeServer.get_source(object)}
      _ -> {:error, :not_implemented}
    end
  end

  @doc "Returns online docs for current position in line"
  def online_docs_url(line, current_column, opts \\ []) do
    case find_object(line, current_column, opts) do
      {type, _} = object when type in @supported_types ->
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
    mod = module_for_current_alias(aliases, tokens, index, env)
    type = if elixir_module?(mod), do: :module, else: :erlang_module

    {type, mod}
  end

  defp process_token({{identifier, _location, func}, identifier_index}, tokens, env)
    when identifier in [:identifier, :paren_identifier]
  do
    arity = calculate_arity(tokens, identifier_index)

    case Enum.at(tokens, identifier_index - 1) do
      {{:., _,}, index} ->
        case Enum.at(tokens, index - 1) do
          {{:atom, _, mod}, _} -> {:erlang_function, {mod, {func, arity}}}
          {{:aliases, _, aliases}, index} ->
            mod = module_for_current_alias(aliases, tokens, index, env)
            function_source({mod, {func, arity}})
         _ -> nil
        end
      _ ->
        resolve_imported({func, arity}, env) |> function_source
    end
  end

  defp process_token(_, _, _), do: nil
  defp prev_aliases(_tokens, index) when index < 2, do: []
  defp prev_aliases(tokens, index) do
    tokens |> Enum.slice(0..index-1) |> Enum.reverse |> fetch_aliases([])
  end

  defp calculate_arity(tokens, index) do
    right_tokens = Enum.slice(tokens, index..-1)

    params_tokens = case Enum.at(tokens, index) do
      {{:identifier, _, _}, _}->
        fetch_params(right_tokens, [])
      {{:paren_identifier, _, _}, _}->
        fetch_params(right_tokens, [], [])
    end

    case :elixir_parser.parse(params_tokens) do
      {:ok, {_identifer, _, nil}} -> 0
      {:ok, {_identifer, _, params}} ->
        count = Enum.count(params)
        left_tokens = Enum.slice(tokens, 0..index-1)

        if piped?(left_tokens) do
          count + 1
        else
          count
        end
      _ -> 0
    end
  end

  defp fetch_params([], [{:stab_op, _, :->}|_] = param_tokens) do
    Enum.reverse([{:end, {0,0,0}}, {:number, {0,0,0}, 1}|param_tokens])
  end

  defp fetch_params([], param_tokens) do
    Enum.reverse(param_tokens)
  end

  defp fetch_params([{token, _}|rest], param_tokens), do: fetch_params(rest, [token|param_tokens])

  defp fetch_params([], _, stack) when length(stack) > 0 do
    []
  end
  defp fetch_params([], param_tokens, _) do
    Enum.reverse(param_tokens)
  end

  defp fetch_params([{{:")", _} = end_token, _}|_], param_tokens, [:"("]) do
    Enum.reverse([end_token | param_tokens])
  end

  defp fetch_params([{{:")", _} = token, _}|rest], param_tokens, [:"("|rest_stack]) do
    fetch_params(rest, [token|param_tokens], rest_stack)
  end

  defp fetch_params([{{:"(" = par, _} = token, _}|rest], param_tokens, stack) do
    fetch_params(rest, [token|param_tokens], [par|stack])
  end
  defp fetch_params([{token, _}|rest], param_tokens, stack), do: fetch_params(rest, [token|param_tokens], stack)

  defp fetch_aliases([{{:., _},_} | rest], res), do: fetch_aliases(rest, res)
  defp fetch_aliases([{{:aliases, _, [aliases]},_} | rest], res), do: fetch_aliases(rest, [aliases|res])
  defp fetch_aliases(_, res), do: res

  defp piped?([]), do: false
  defp piped?([{{:arrow_op, _, :|>},_}|_]), do: true
  defp piped?([_|rest]), do: piped?(rest)


  defp module_for_current_alias(aliases, tokens, index, env) do
    prev_aliases(tokens, index) ++ aliases
    |> Module.concat
    |> resolve_alias(env)
  end

  defp resolve_alias(mod, nil = _nil), do: mod
  defp resolve_alias(mod, %{aliases: aliases} = _env) do
    Enum.find_value(aliases, &(elem(&1,0) == mod && elem(&1,1))) || mod
  end

  defp resolve_imported(_func_name, nil), do: nil
  defp resolve_imported(func, %{functions: functions} = _env) do
    Enum.find_value functions, fn({mod, functions})->
      Enum.find(functions, &(&1 == func)) && {mod, func}
    end
  end

  defp function_source({mod, {func, arity}}) do
    if elixir_module?(mod) do
      {:function, {mod, {func, arity}}}
    else
      {:erlang_function, {mod, {func, arity}}}
    end
  end

  defp function_source(_) do
    nil
  end
end
