defmodule Ilexir.Linter.Credo do
  alias Ilexir.QuickFix.Item

  def run(file, content) do
    credo_source = Credo.SourceFile.parse(content, file)
    %{issues: credo_issues} = Credo.Check.Runner.run(credo_source, Credo.Config.read_or_default([]))
    to_fix_items(credo_issues)
  end

  defp to_fix_items(credo_issues) do
    Enum.map(credo_issues, &to_fix_item/1)
  end

  defp to_fix_item(%Credo.Issue{message: message, line_no: line, filename: filename}) do
    %Item{file: filename, text: message, type: :warning, location: location(line)}
  end

  defp location(line) when is_integer(line) do
    %Item.Location{line: line}
  end

  defp location({line, col_start, col_end}) do
    %Item.Location{line: line, col_start: col_start, col_end: col_end}
  end

  defp location(_location) do
    %Item.Location{line: 1}
  end
end
