defmodule Ilexir.Autocomplete.OmniFunc do
  @moduledoc """
  Implements interface for "omnifunc" vim completion.

  See neovim help for more info(`h omnifunc` and `h complete-functions`)
  """
  alias Ilexir.Code.Server, as: CodeServer

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
            expr = aliases |> List.last |> to_string
            mod = Module.concat(List.delete_at(aliases, -1))
            expand_elixir_modules(expr, mod, env)
          {:ok, {{:., _, [{:__aliases__, _, aliases}, _expr]}, _, _}} ->
            mod = Module.concat(aliases)
            funcs = expand_elixir_functions(mod, expression, env)
          {:ok, {{:., _, [mod, _]}, _, _}} ->
            expand_erlang_functions(mod, expression)
          _ ->
            if String.ends_with?(founded, ".") do
              founded = String.slice(founded, 0..-2)

              case Code.string_to_quoted(founded) do
                {:ok, mod} when is_atom(mod) ->
                  expand_erlang_functions(mod, "")
                {:ok, {:__aliases__, _, aliases}} ->
                  root_module = Module.concat(aliases)
                  mods = expand_elixir_modules("", root_module, env)
                  funcs = expand_elixir_functions(root_module, "", env)
                  funcs ++ mods
              end
            else
              []
            end
        end
      _ ->
        expanded_functions = expand_imported(expression, env.functions)
        expanded_macros = expand_imported(expression, env.macros)
        expanded_functions ++ expanded_macros ++ expand_aliases(expression, env) ++ expand_elixir_modules(expression, Elixir, env)
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
      mod_name = to_string(mod)
      if !String.starts_with?(mod_name, "Elixir") && String.starts_with?(mod_name, expression) do
        [erl_mod_to_comlete_item(mod) | result]
      else
        result
      end
    end
  end

  defp erl_mod_to_comlete_item(mod) do
    text = to_string(mod)
    %CompletedItem{text: text, abbr: text, type: "m", short_desc: "erlang module"}
  end

  defp expand_elixir_modules(expression, root, env) do
    CodeServer.get_modules |> Enum.reduce([], fn(mod, mods)->
      mod_name = to_string(mod)
      root_name = to_string(resolve_alias(root, env))

      if String.starts_with?(mod_name, root_name <> "." <> expression) do
        [elixir_mod_to_complete_item(mod, root_name) | mods]
      else
        mods
      end
    end)
  end

  defp expand_aliases(expression, env) do
    Enum.reduce env.aliases, [], fn({aliased_mod, original_mod}, aliased_mods)->
      mod_name = to_string(aliased_mod)

      find_expression = "Elixir." <> expression
      if String.starts_with?(mod_name, find_expression) do
        text = mod_name |> String.trim_leading("Elixir.")

        type = "a(#{String.trim_leading(to_string(original_mod), "Elixir.")})"
        [%CompletedItem{text: text, abbr: text, type: type, short_desc: description_from_doc(original_mod)} | aliased_mods]
      else
        aliased_mods
      end
    end
  end

  defp expand_elixir_functions(mod, expression, env) do
    mod = resolve_alias(mod, env)
    module_exports(mod) |> Enum.reverse |> Enum.reduce([], fn({func, arity}, result)->
      func_name = to_string(func)
      if String.starts_with?(func_name, expression) && !function_for_internal_use?(func_name) do
        [to_complete_item(mod, {func, arity}) | result]
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
    beam_specs = Kernel.Typespec.beam_specs(mod)

    Enum.reduce beam_specs, [], fn({{func, _arity},_}, result)->
      func_name = to_string(func)
      if String.starts_with?(to_string(func), expression) do
        [%CompletedItem{text: func_name, abbr: func_name, type: "def", short_desc: "No documentation."} | result]
      else
        result
      end
    end
  end

  defp expand_imported(expression, definitions) do
    Enum.reduce definitions, [], fn({mod, funcs}, result)->
      founded_funcs = Enum.filter_map funcs, fn({name, _arity})->
        String.starts_with?(to_string(name), expression)
      end, fn({name, arity})->
        to_complete_item(mod, {name, arity})
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
      _ ->
        "No documentation found."
    end
  end

  defp to_complete_item(mod, {funcname, arity} = f) do
    func_docs = CodeServer.get_elixir_docs(mod, :docs)
    case func_data_from_docs(func_docs, f) do
      nil ->
        %CompletedItem{
          text: to_string(funcname),
          abbr: "#{funcname}/#{arity}",
          type: "def",
          short_desc: short_desc(nil)
        }
      {_,_,_,_, nil = _desc} = func_data ->
        behaviour_mods = mod.__info__(:attributes)[:behaviour] || []
        callback_docs = CodeServer.get_elixir_docs(List.first(behaviour_mods), :callback_docs)
        new_desc = desc_from_callback_docs(callback_docs, f)
        func_data = put_elem(func_data, 4, new_desc)

        item_from_func_doc_data(func_data)
      func_data ->
        item_from_func_doc_data(func_data)
    end
  end

  defp short_desc(nil), do: "No description found."
  defp short_desc(false), do: "No description provided."
  defp short_desc(desc), do: desc |> String.split("\n") |> List.first

  defp func_data_from_docs([], _), do: nil
  defp func_data_from_docs(docs, {funcname, _arity}) do
    Enum.find(docs, fn({{func, _},_,_,_,_})-> func == funcname end)
  end

  defp desc_from_callback_docs([], _), do: nil
  defp desc_from_callback_docs(docs, {funcname, _arity}) do
    Enum.find_value(docs, fn({{func, _},_,_, desc})-> func == funcname && desc end)
  end

  defp item_from_func_doc_data({{funcname, _arity},_, type, quoted_params, desc} = _doc_data) do
    params = quoted_params |> Macro.to_string |> String.slice(1..-2)

    %CompletedItem{
      text: to_string(funcname),
      abbr: "#{funcname}(#{params})",
      type: to_string(type),
      short_desc: short_desc(desc)
    }
  end
end
