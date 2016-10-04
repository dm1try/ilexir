defmodule Ilexir.Linter.Ast do
  alias Ilexir.QuickFix.Item

  def run(file, content) do
    case Code.string_to_quoted(content, file: file) do
      {:error, {location, error, token}} ->
        [%Item{file: file, text: error_text(error, token), type: :error, location: item_location(location)}]
      _ ->
       []
    end
  end

  def error_text(error, token) when is_bitstring(error) do
    error<>token
  end

  def error_text(error, token) when is_tuple(error) do
    error_text = error |> Tuple.to_list |> Enum.join

    error_text(error_text, token)
  end

  def error_text(error, token) do
    "#{inspect error} #{token}"
  end

  def item_location(location) when is_integer(location) do
    %Item.Location{line: location}
  end

  def item_location({line, col_start, col_end}) do
    %Item.Location{line: line, col_start: col_start, col_end: col_end}
  end
end
