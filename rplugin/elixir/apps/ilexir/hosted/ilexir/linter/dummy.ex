defmodule Ilexir.Linter.Dummy do
  @moduledoc """
  Only for tests.
  """
  alias Ilexir.QuickFix.Item

  def run(file, "no errors") do
    []
  end

  def run(file, content) do
    [%Item{file: file, text: "dummy error", type: :error, location: %Item.Location{}}]
  end
end
