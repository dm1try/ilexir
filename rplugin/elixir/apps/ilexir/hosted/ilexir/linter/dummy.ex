defmodule Ilexir.Linter.Dummy do
  @moduledoc """
  Only for tests.
  """
  alias Ilexir.QuickFix.Item

  def run(_file, "no errors") do
    []
  end

  def run(file, _content) do
    [%Item{file: file, text: "dummy error", type: :error, location: %Item.Location{}}]
  end
end
