defmodule Ilexir.Linter.Credo do
  @moduledoc "Wrapper for credo linting"
  alias Credo.{SourceFile, Check, Config}
  alias Ilexir.QuickFix.Item

  def run(file, content) do
    credo_source = SourceFile.parse(content, file)
    %{issues: credo_issues} = Check.Runner.run(credo_source, Config.read_or_default([]))
    to_fix_items(credo_issues)
  end

  defp to_fix_items(credo_issues) do
    Enum.map(credo_issues, &to_fix_item/1)
  end

  defp to_fix_item(%Credo.Issue{message: message, line_no: line, column: column, filename: filename}) do
    %Item{file: filename, text: message, type: :warning, location: location({line, column})}
  end

  defp location({line, nil}) do
    %Item.Location{line: line}
  end

  defp location({line, column}) when is_number(column) do
    %Item.Location{line: line, col_start: column - 1}
  end

  defp location({line, col_start, col_end}) when is_number(col_start) and is_number(col_end) do
    %Item.Location{line: line, col_start: col_start, col_end: col_end}
  end

  defp location(_location) do
    %Item.Location{line: 1}
  end
end
