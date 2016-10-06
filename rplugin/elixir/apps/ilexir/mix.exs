defmodule Ilexir.Mixfile do
  use Mix.Project

  def project do
    [app: :ilexir,
     version: "0.1.0",
     build_path: "../../_build",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     preferred_cli_env: [espec: :test],
     elixir: "~> 1.3",
     deps: deps()]
  end

  def application do
    options = [applications: [:logger] , env: [plugin_module: Ilexir.Plugin]]
    if Mix.env != :test, do: options ++ [mod: {Ilexir, []}], else: options
  end

  defp deps do
    [{:nvim, "~> 0.1.2"},
     {:espec, "~> 1.0.0", only: [:dev, :test]}]
  end
end
