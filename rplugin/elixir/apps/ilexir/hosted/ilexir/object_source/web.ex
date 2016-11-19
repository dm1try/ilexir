defmodule Ilexir.ObjectSource.Web do
  @moduledoc false
  alias Ilexir.ObjectSource, as: OS

  alias Ilexir.Code
  import Ilexir.Code.Info, only: [compile_info: 1]

  @spec docs_url(OS.source_object) :: String.t | nil

  @doc "Finds online docs for the given object"
  def docs_url({:module, mod} = object) do
    if Code.elixir_module?(mod) do
      elixir_url(object)
    end
  end

  def docs_url({:function, {mod, {func_name, func_arity}}} = _object) do
    if Code.elixir_module?(mod) do
      module_url = elixir_url({:module, mod})
      func_anchor = "##{func_name}/#{func_arity}"
      "#{module_url}#{func_anchor}"
    end
  end

  def docs_url({:function, {mod, _func_name}} = _object) do
    if Code.elixir_module?(mod) do
      elixir_url({:module, mod})
    end
  end

  def docs_url(_), do: nil

  defp elixir_url({:module, mod}) do
    with app when is_atom(app) <- find_mod_app(mod),
         version when is_bitstring(version) <- find_app_version(app) do

      base_url = Hex.Utils.hexdocs_url(app, version)
      "#{base_url}/#{inspect(mod)}.html"
    end
  end

  defp find_mod_app(mod) do
    source = compile_info(mod)[:source] |> to_string

    case Regex.run(~r/deps\/(\w+)\/lib/, source) do
      [_, app_name] -> String.to_atom(app_name)
      _ -> nil
    end
  end

  defp find_app_version(app) do
    Application.spec(app)[:vsn] |> to_string
  end
end

