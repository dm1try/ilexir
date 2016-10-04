defmodule Ilexir.QuickFix.Item do
  defstruct [:file, :text, :type, :location]

  defmodule Location do
    defstruct [line: 1, col_start: 0,  col_end: -1]
  end
end
