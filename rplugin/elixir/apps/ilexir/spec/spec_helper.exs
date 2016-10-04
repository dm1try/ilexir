Code.compiler_options(ignore_module_conflict: true)

defmodule Ilexir.Fixtures do
  def xdg_home_path do
    "#{__DIR__}/fixtures/xdg_home"
  end

  def test_elixir_file_path do
    "#{__DIR__}/fixtures/some_test_file.ex"
  end
end

