defmodule Ilexir.Utils.Web do
  @spec open_url(String.t) :: :ok | :error
  @doc "Opens the given url using OS binary"
  def open_url(url) do
    binary = case :os.type do
      {:unix, :linux} -> "xdg-open"
      {:unix, _} -> "open"
      _ -> nil
    end

    run_cmd(binary, url)
  end

  defp run_cmd(nil, _url), do: :error

  defp run_cmd(binary, url) do
    case System.cmd binary, [url] do
      {_, 0} -> :ok
      _ -> :error
    end
  rescue ErlangError -> :error
  end
end
