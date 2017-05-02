defmodule Ilexir.UserConfig.NVim do
  @behaviour Ilexir.UserConfig
  import NVim.Session

  def get(name, default \\ nil) do
    case nvim_get_var(build_name(name)) do
      {:ok, value} -> value
      _ -> default
    end
  end

  def set(name, value) do
    case nvim_set_var(build_name(name), value) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp build_name(name) do
    "ilexir_#{name}"
  end
end
