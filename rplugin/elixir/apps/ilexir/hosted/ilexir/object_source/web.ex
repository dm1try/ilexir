defmodule Ilexir.ObjectSource.Web do
  @moduledoc false
  alias Ilexir.ObjectSource, as: OS
  import Ilexir.Code.Info, only: [compile_info: 1]

  @elixir_docs_base_url "http://elixir-lang.org/docs"
  @erlang_docs_base_url "http://erlang.org/doc/man"

  @spec docs_url(OS.source_object) :: String.t | nil
  @doc "Finds online docs for the given object"
  def docs_url({:module, mod}) do
    with {type, app} <- find_mod_app(mod),
         version when not is_nil(version) <- app_version(app) do

      mod_name = inspect(mod)

      case type do
        :package ->
          hex_docs_base_url = Hex.Utils.hexdocs_url(app, version)
          "#{hex_docs_base_url}/#{mod_name}.html"
        :core ->
          version_without_patch = String.replace(version, ~r/\.\d+\z/, "")
          "#{@elixir_docs_base_url}/v#{version_without_patch}/#{app}/#{mod_name}.html"
      end
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

  def docs_url({:erlang_module, mod}) do
    with {type, app} <- find_erlang_app(mod) do
      case type do
        :stdlib -> "#{@erlang_docs_base_url}/#{app}.html"
      end
    end
  end

  def docs_url({:erlang_function, {mod, {func_name, func_arity}}}) do
    case docs_url({:erlang_module, mod}) do
      app_url when is_bitstring(app_url) ->
        func_anchor = "##{func_name}-#{func_arity}"
        "#{app_url}#{func_anchor}"
      _ -> nil
    end
  end

  def docs_url(_), do: nil

  defp find_mod_app(mod) do
    source = mod_source(mod)

    case Regex.run(~r/deps\/(\w+)\/lib/, source) do
      [_, app_name] -> {:package, String.to_atom(app_name)}
      _ -> case Regex.run(~r/lib\/(\w+)\/lib/, source) do
        [_, core_app_name] -> {:core, String.to_atom(core_app_name)}
        _ -> nil
      end
    end
  end

  defp find_erlang_app(mod) do
    case compile_info(mod) do
      [] -> {:stdlib, :erlang}
      info when is_list(info) ->
        source = to_string(info[:source])
        case Regex.run(~r/stdlib\/src\/(\w+)\.erl/, source) do
          [_, app_name] -> {:stdlib, String.to_atom(app_name)}
          _ -> nil
        end
    end
  end

  defp mod_source(mod) do
    compile_info(mod)[:source] |> to_string
  end

  defp app_version(app) do
    if version = Application.spec(app, :vsn) do
      to_string(version)
    end
  end
end

