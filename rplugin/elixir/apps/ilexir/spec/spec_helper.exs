Code.compiler_options(ignore_module_conflict: true)

defmodule Ilexir.Fixtures do
  def xdg_home_path do
    "#{__DIR__}/fixtures/xdg_home"
  end

  def test_elixir_file_path do
    "#{__DIR__}/fixtures/some_test_file.ex"
  end

  def test_elixir_mix_project_path do
    "#{__DIR__}/fixtures/dummy_mix_app"
  end
end

defmodule Ilexir.Test.Autocomplete do
  defmodule ItemAssertion do

    use ESpec.Assertions.Interface

    defp match(results, expected_text) do
      result = Enum.any?(results, &(&1.text == expected_text))

      {result, result}
    end

    defp success_message(results, text, _result, positive) do
      to = if positive, do: "is", else: "is not"
      Enum.any?(results, &(&1.text == "timer"))
      "`#{inspect results}` #{to} include the item with #{text}."
    end

    defp error_message(results, text, _result, positive) do
      to = if positive, do: "to", else: "not to"
      "Expected `#{inspect results}` #{to} include the item with '#{text}' text."
    end
  end

  defmodule Assertions do
    def have_completed_item(expected_text), do: {ItemAssertion, expected_text}
  end
end
