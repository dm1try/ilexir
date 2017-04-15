defmodule Ilexir.Autocomplete.OmniFunc do
  @moduledoc """
  Implements interface for "omnifunc" vim completion.

  See neovim help for more info(`h omnifunc` and `h complete-functions`)
  """
  alias Ilexir.Code.Server, as: CodeServer

  import Ilexir.Code, only: [elixir_module?: 1]

  defmodule CompletedItem do
    defstruct [:text, :abbr, :type, :short_desc]
  end

  def find_complete_position("", current_column), do: current_column
  def find_complete_position(line, current_column) do
    line = String.slice(line, 0..current_column-1)
    line = String.replace(line, ~r/\w+\z/, "")

    String.length(line)
  end

  def expand(line, current_column, expression, args \\ []) do
    env = Keyword.get(args, :env, %{functions: [], macros: [], aliases: []})
    line = String.slice(line, 0..current_column - 1)

    case Regex.run(~r/[A-Za-z.:_]+\z/, line) do
      [":"] ->
         expand_erlang_modules(expression)
      [founded] ->
        case Code.string_to_quoted(founded <> expression) do
          {:ok, mod} when is_atom(mod) ->
            expand_erlang_modules(expression)
          {:ok, {:__aliases__, _, aliases}} ->
            expr = aliases |> List.last |> Atom.to_string
            root_module = Module.concat(List.delete_at(aliases, -1)) |> resolve_alias(env)
            expand_elixir_modules(expr, root_module)
          {:ok, {{:., _, [{:__aliases__, _, aliases}, _expr]}, _, _}} ->
            mod = Module.concat(aliases) |> resolve_alias(env)

            if elixir_module?(mod) do
              expand_elixir_functions(mod, expression)
            else
              expand_erlang_functions(mod, expression)
            end
          {:ok, {{:., _, [mod, _]}, _, _}} ->
            expand_erlang_functions(mod, expression)
          _ ->
            if String.ends_with?(founded, ".") do
              founded = String.slice(founded, 0..-2)

              case Code.string_to_quoted(founded) do
                {:ok, mod} when is_atom(mod) ->
                  expand_erlang_functions(mod, "")
                {:ok, {:__aliases__, _, aliases}} ->
                  root_module = Module.concat(aliases) |> resolve_alias(env)

                  if elixir_module?(root_module) do
                    mods = expand_elixir_modules("", root_module)
                    funcs = expand_elixir_functions(root_module, "")
                    funcs ++ mods
                  else
                    expand_erlang_functions(root_module, "")
                  end
                _ -> []
              end
            else
              []
            end
        end
      _ ->
        expanded_functions = expand_imported(expression, env.functions)
        expanded_macros = expand_imported(expression, env.macros)
        expanded_functions ++ expanded_macros ++ expand_aliases(expression, env) ++ expand_elixir_modules(expression, Elixir)
    end
  end

  defp resolve_alias(mod, nil = _env), do: mod
  defp resolve_alias(mod, env) do
    case Enum.find(env.aliases, fn({as, _original})-> as == mod end) do
      {_, original} -> original
      _ -> mod
    end
  end

  defp expand_erlang_modules(expression) do
    Enum.reduce CodeServer.get_modules, [], fn(mod, result)->
      mod_name = Atom.to_string(mod)

      if !match_expression?(mod_name, "Elixir") && match_expression?(mod_name, expression) do
        [erl_mod_to_comlete_item(mod) | result]
      else
        result
      end
    end
  end

  defp erl_mod_to_comlete_item(mod) do
    text = Atom.to_string(mod)
    %CompletedItem{text: text, abbr: text, type: "m", short_desc: "erlang module"}
  end

  defp expand_elixir_modules(expression, root) do
    CodeServer.get_modules |> Enum.reduce([], fn(mod, mods)->
      root_name = Atom.to_string(root)
      final_expression = "#{root_name}.#{expression}"

      if match_expression?(mod, final_expression) do
        [elixir_mod_to_complete_item(mod, root_name) | mods]
      else
        mods
      end
    end)
  end

  defp expand_aliases(expression, env) do
    Enum.reduce env.aliases, [], fn({aliased_mod, _original_mod} = mod_relation, aliased_mods)->
      if match_expression?(aliased_mod, "Elixir.#{expression}") do
        [aliased_to_complete_item(mod_relation) | aliased_mods]
      else
        aliased_mods
      end
    end
  end

  defp aliased_to_complete_item({aliased_mod, original_mod}) do
    text = inspect(aliased_mod)
    type = "a(#{inspect(original_mod)})"

    %CompletedItem{
      text: text,
      abbr: text,
      type: type,
      short_desc: description_from_doc(original_mod)
    }
  end

  defp expand_elixir_functions(mod, expression) do
    module_exports(mod) |> Enum.reverse |> Enum.reduce([], fn({func, _arity} = f, result)->
      func_name = Atom.to_string(func)
      if String.starts_with?(func_name, expression) && !function_for_internal_use?(func_name) do
        func_docs = CodeServer.get_elixir_docs(mod, :docs)
        case func_data_from_docs(func_docs, f) do
          nil -> result
          {_,_,_,_, nil = _desc} = func_data_with_empty_desc ->
            behaviour_mods = mod.__info__(:attributes)[:behaviour] || []
            callback_docs = CodeServer.get_elixir_docs(List.first(behaviour_mods), :callback_docs)
            new_desc = desc_from_callback_docs(callback_docs, f)
            func_data = put_elem(func_data_with_empty_desc, 4, new_desc)

            [item_from_func_doc_data(func_data) | result]
          func_data ->
            [item_from_func_doc_data(func_data) | result]
        end
      else
        result
      end
    end)
  end

  defp function_for_internal_use?(func_name), do: String.starts_with?(func_name, "_")

  defp module_exports(mod) do
    if String.starts_with?(to_string(mod), "Elixir") do
      mod.__info__(:functions) ++ mod.__info__(:macros)
    else
      mod.module_info(:exports)
    end
  rescue UndefinedFunctionError -> []
  end

  defp expand_erlang_functions(mod, expression) do
    mod_exports = module_exports(mod)
    with specs when is_list(specs) <- Kernel.Typespec.beam_specs(mod) do
      Enum.reduce specs, [], fn
        {{func, arity},_} = spec_data, result ->
          if match_expression?(func, expression) && {func, arity} in mod_exports do
            erlang_func_to_complete_items(spec_data) ++ result
          else
            result
          end
        {{^mod, func, arity}, types}, result ->
          if match_expression?(func, expression) && {func, arity} in mod_exports do
            spec_data = {{func, arity}, types}
            erlang_func_to_complete_items(spec_data) ++ result
          else
            result
          end
          _, result -> result
      end
    else _ -> []
    end
  end

  defp expand_imported(expression, definitions) do
    Enum.reduce definitions, [], fn({mod, funcs}, result)->
      func_docs = CodeServer.get_elixir_docs(mod, :docs)

      founded_funcs = Enum.filter_map funcs,
        fn({name, _arity})->
          match_expression?(name, expression)
        end,
        fn(func)->
          func_data = func_data_from_docs(func_docs, func)|| func_with_defaults_data_from_docs(func_docs, func)

          if func_data do
            item_from_func_doc_data(func_data)
          else
            item_from_func_without_doc(func)
          end
        end

      founded_funcs ++ result
    end
  end

  defp elixir_mod_to_complete_item(mod, root_name) do
    text = mod |> Atom.to_string |> String.trim_leading(root_name<>".")
    %CompletedItem{text: text, abbr: text, type: "m", short_desc: description_from_doc(mod)}
  end

  defp description_from_doc(module) do
    case CodeServer.get_elixir_docs(module, :moduledoc) do
      {_line, desc} -> short_desc(desc)
      _ -> "No documentation found."
    end
  end

  defp erlang_func_to_complete_items({{funcname, _arity}, func_data} = _beam_spec_data) when is_list(func_data) do
    Enum.map func_data, fn(data) ->
      params_string = erlang_func_params(data) |> Enum.join(", ")

      %CompletedItem{
        text: Atom.to_string(funcname),
        abbr: "#{funcname}(#{params_string})",
        type: "def",
        short_desc: short_desc(nil)
      }
    end
  end

  defp erlang_func_params(params) when is_list(params) do
    erlang_func_params(List.first(params))
  end

  defp erlang_func_params({:type, _, :bounded_fun, params_data}) do
    erlang_func_params(params_data)
  end

  defp erlang_func_params({:type, _, :fun, [{:type, _, :product, params_data}|_]}) do
    Enum.map params_data, fn
      {:var, _, var_name} -> var_name |> Atom.to_string |> Macro.underscore
      {:atom, _, atom} -> ":#{atom}"
      {type, _, name, _} when type in [:type, :user_type] -> Atom.to_string(name)
      a -> inspect(a)
    end
  end

  defp erlang_func_params(_), do: []

  defp short_desc(nil), do: "No description found."
  defp short_desc(false), do: "No description provided."
  defp short_desc(desc), do: desc |> String.split("\n") |> List.first

  defp func_data_from_docs([], _), do: nil
  defp func_data_from_docs(docs, func) do
    Enum.find(docs, &(elem(&1, 0) == func))
  end

  defp func_with_defaults_data_from_docs(docs, {funcname, arity} = func) do
    data = Enum.find docs, fn({{func, founded_arity},_,_,_,_})-> founded_arity >= arity && func == funcname end

    if data do
      put_elem(data, 0, func)
    end
  end

  defp desc_from_callback_docs([], _), do: nil
  defp desc_from_callback_docs(docs, func) do
    Enum.find_value(docs, &(elem(&1, 0) == func && elem(&1, 3)))
  end

  defp item_from_func_doc_data({{funcname, arity},_, type, quoted_params, desc} = _doc_data) do
    params = quoted_params |> Enum.take(arity) |> Macro.to_string |> String.slice(1..-2)

    %CompletedItem{
      text: Atom.to_string(funcname),
      abbr: "#{funcname}(#{params})",
      type: Atom.to_string(type),
      short_desc: short_desc(desc)
    }
  end

  defp item_from_func_without_doc({name, arity}) do
    %CompletedItem{text: "#{name}", abbr: "#{name}/#{arity}", type: "def", short_desc: "No docs found."}
  end

  defp match_expression?(object, expression) when is_atom(object) do
    match_expression?(Atom.to_string(object), expression)
  end

  defp match_expression?(object, expression) when is_bitstring(object) do
    String.starts_with?(object, expression)
  end
end
