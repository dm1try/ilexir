defmodule Ilexir.HostApp do
  @moduledoc false

  defstruct [:id,
             :name,
             :remote_name,
             :exec_path, # can be overridedn by runner
             :path,
             mix_app?: false,
             env: "dev",
             status: :not_started,
             meta: %{}]

  @hosted_path Path.expand("#{__DIR__}/../../hosted")

  @doc "Build application struct that based on provided path and args."
  def build(path, args \\ []) do
    args =
      args
      |> Keyword.put_new(:app_name, Path.basename(path))
      |> Keyword.put_new(:env, "dev")

    mix_app? = mix_app?(path)
    remote_name = remote_name(args[:app_name], args[:env])

    %__MODULE__{
      name: args[:app_name],
      remote_name: remote_name,
      exec_path: exec_path(path, args, mix_app?, remote_name),
      path: path,
      env: args[:env],
      mix_app?: mix_app?
    }
  end

  defp remote_name(app_name, env) do
    {:ok, hostname} = :inet.gethostname
    :"#{"#{app_name}_#{env}"}@#{hostname}"
  end

  @test_dirs ["spec", "test"]

  @doc "looks up a suitable app for provided path"
  def lookup(file_path, apps) do
    Enum.find apps, fn(%{env: env, path: path})->
      if String.contains?(file_path, path) do
        relative = Path.relative_to(file_path, path)
        test_dir? = Enum.any? @test_dirs, fn(test_dir)->
          String.starts_with?(relative, test_dir)
        end

        if test_dir?, do: env == "test", else: env != "test"
      end
    end
  end

  defp exec_path(path, args, mix_app?, remote_name) do
    mix_env = if mix_app?, do: "MIX_ENV=#{args[:env]}", else: ""
    exec_line = "cd #{path} && #{mix_env} elixir --no-halt --sname #{remote_name}"

    if mix_app? do
      script = Keyword.get(args, :script, "run -e 'Application.load(Mix.Project.config[:app])' --no-start")
      "#{exec_line} -S mix #{script}"
    else
      exec_line
    end
  end

  @doc "Load a file from hosted directory to hosted application"
  def load_hosted_file(app, file_path) do
    path = Path.join(@hosted_path, file_path)
    call(app, Code, :load_file, [path])
  end

  @doc "Makes a remote call to hosted application"
  def call(app, module, method, args \\ []) do
    app.remote_name
    |> :rpc.call(module, method, args)
    |> rpc_result
  end

  def block_call(app, module, method, args \\ []) do
    app.remote_name
    |> :rpc.block_call(module, method, args)
    |> rpc_result
  end

  defp mix_app?(path) do
    Path.join([path, "mix.exs"]) |> File.exists?
  end

  defp rpc_result({:badrpc, {_, error}}), do: {:error, error}
  defp rpc_result({:badrpc, error}), do: {:error, error}
  defp rpc_result(result), do: result
end
