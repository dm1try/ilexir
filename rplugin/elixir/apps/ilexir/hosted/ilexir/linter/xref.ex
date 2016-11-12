defmodule Ilexir.Linter.Xref do
  @moduledoc """
  Xref linter.
  """
  alias Ilexir.QuickFix.Item

  def run(file, _content) do
    {_, runtime_dispatches} = Ilexir.Xref.Server.get_dispatches(file)

    runtime_dispatches
      |> unreachable_calls
      |> unreachable_calls_to_fix_items(file)
  end

  defp unreachable_calls(runtime_dispatches) do
    Enum.map(runtime_dispatches, fn({mod, calls}) ->
      Enum.find_value calls, fn ({{function, arity}, lines})->
        case Code.ensure_loaded(mod) do
          {:module, ^mod} ->
            !function_exported?(mod, function, arity) && {mod, {function, arity}, lines}
          _ ->
            {mod, lines}
        end
      end
    end) |> Enum.filter(&(&1 != nil))
  end

  defp unreachable_calls_to_fix_items(calls, file) do
    Enum.flat_map(calls, &(unreachable_call_to_fix_item(&1, file)))
  end

  defp unreachable_call_to_fix_item({module, lines}, file) do
    Enum.map lines, fn(line) ->
      %Item{
        file: file,
        text: "Module #{mod_name(module)} is unreachable.",
        type: :warning,
        location: %Item.Location{line: line}
      }
    end
  end

  defp unreachable_call_to_fix_item({module, {function, arity}, lines}, file) do
    Enum.map lines, fn(line) ->
      %Item{
        file: file,
        text: "function #{mod_name(module)}.#{function}/#{arity} is unreachable.",
        type: :warning,
        location: %Item.Location{line: line}
      }
    end
  end

  defp mod_name(mod) do
    mod |> to_string |> String.replace_leading("Elixir.", "")
  end
end
