defmodule Ilexir.ObjectSource.Web do
  @moduledoc false
  alias Ilexir.ObjectSource, as: OS
  import Ilexir.Code.Info, only: [compile_info: 1]

  @spec docs_url(OS.source_object) :: String.t | nil
  @doc "Finds online docs for the given object"
  def docs_url({:module, mod}) do
    with app when is_atom(app) <- find_mod_app(mod),
         version when is_bitstring(version) <- find_app_version(app) do

      base_url = Hex.Utils.hexdocs_url(app, version)
      "#{base_url}/#{inspect(mod)}.html"
    else
      _ -> nil
    end
  end

  def docs_url({:function, {mod, {func_name, func_arity}}}) do
    case docs_url({:module, mod}) do
      module_url when is_bitstring(module_url) ->
        func_anchor = "##{func_name}/#{func_arity}"
        "#{module_url}#{func_anchor}"

      _ -> nil
    end
  end

  def docs_url({:function, {mod, _func_name}}) do
    docs_url({:module, mod})
  end

  def docs_url(_), do: nil

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

