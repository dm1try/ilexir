defmodule Ilexir.HostApp do
  @moduledoc """
  Provides the interface for management hosted applications.
  """
  defstruct [:name, :path, mix_app?: false, env: "dev"]

  @runner Application.get_env(:ilexir, :host_app_runner) || Ilexir.HostApp.NvimTerminalRunner

  @fallback_failure_count 30
  @fallback_timeout 400

  @doc "Returns remote name for hosted app."
  def remote_name(%Ilexir.HostApp{name: app_name, env: env}) do
    {:ok, hostname} = :inet.gethostname
    :"#{app_name}_#{env}@#{hostname}"
  end

  @doc """
  Starts hosted application.

  Ensures that the application is running and available for code evaluation.
  """
  def start(path, args \\ [], runner_opts \\ []) do
    app_name = Keyword.get(args, :app_name, Path.basename(path))

    with {:ok, app} <-  @runner.start_app(%__MODULE__{
                                          name: app_name,
                                          path: path,
                                          mix_app?: mix_app?(path)
                                        }, runner_opts),
      :ok <- wait_for_running(app) do
        {:ok, app}
      else
        error -> error
      end
  end

  @doc "Stops the app"
  def stop(app) do
    :rpc.call(remote_name(app), :init, :stop, [])
    wait_for_stopping(app)
  end

  @doc "Checks if the app is running"
  def running?(app_name) do
    Node.ping(remote_name(app_name)) == :pong
  end

  def prepend_code_path(app_name, code_path) do
    app_name
      |> remote_name
      |> :rpc.call(Code, :prepend_path, [code_path])
  end

  def load_file(app, file_path) do
    app
    |> remote_name
    |> :rpc.call(Code, :load_file, [file_path])
  end

  def compile_string(app, string, file) do
    app
    |> remote_name
    |> :rpc.call(Code, :compile_string, [string, file])
  end

  def eval_string(app, string, bindings, opts \\ []) do
    app
    |> remote_name
    |> :rpc.call(Code, :eval_string, [string, bindings, opts])
  end

  def call(app, module, method, args \\ []) do
    app
    |> remote_name
    |> :rpc.call(module, method, args)
  end

  defp mix_app?(path) do
    Path.join([path, "mix.exs"]) |> File.exists?
  end

  defp wait_for_stopping(app, failure_count \\ @fallback_failure_count)
  defp wait_for_stopping(_app, 0), do: {:error, :not_still_running}
  defp wait_for_stopping(app, failure_count) do
    if running?(app) do
      :timer.sleep @fallback_timeout
      wait_for_stopping(app, failure_count - 1)
    else
      :ok
    end
  end
  defp wait_for_running(app, failure_count \\ @fallback_failure_count)
  defp wait_for_running(_app, 0), do: {:error, :node_not_running}
  defp wait_for_running(%{mix_app?: false} = app, failure_count) do
    if running?(app) do
      wait_for_code_server_running(app)
    else
      :timer.sleep @fallback_timeout
      wait_for_running(app, failure_count - 1)
    end
  end

  defp wait_for_running(%{mix_app?: true} = app, failure_count) do
    if running?(app) do
      wait_for_app_loaded(app)
    else
      :timer.sleep @fallback_timeout
      wait_for_running(app, failure_count - 1)
    end
  end

  defp wait_for_code_server_running(app, failure_count \\ @fallback_failure_count)
  defp wait_for_code_server_running(_app, 0), do: {:error, :code_server_nod_running}
  defp wait_for_code_server_running(app, failure_count) do
    if Ilexir.HostApp.call(app, :elixir_code_server, :module_info, []) do
      :ok
    else
      :timer.sleep @fallback_timeout
      wait_for_code_server_running(app, failure_count - 1)
    end
  end

  defp wait_for_app_loaded(app, failure_count \\ @fallback_failure_count)
  defp wait_for_app_loaded(_app, 0), do: {:error, :application_not_loaded}
  defp wait_for_app_loaded(app, failure_count) do
    apps = Ilexir.HostApp.call(app, :application, :loaded_applications, [])
    if Enum.any?(apps, fn({app_name, _, _})-> app_name == String.to_atom(app.name) end) do
      :ok
    else
      :timer.sleep @fallback_timeout
      wait_for_app_loaded(app, failure_count - 1)
    end
  end
end
