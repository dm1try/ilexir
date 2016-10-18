defmodule Ilexir.HostApp.DummyRunner do
  alias Ilexir.HostApp, as: App

  @behaviour App.Runner

  def start_app(%App{path: path, mix_app?: mix_app?, env: env} = app, opts) do
    runner_id = Keyword.get(opts, :runner_id)
    mix_env = if mix_app?, do: "MIX_ENV=#{env}", else: ""
    exec_line = "cd #{path} && DUMMY_ENV=#{runner_id} #{mix_env} elixir --no-halt --sname #{app.remote_name}"
    exec_line = if mix_app?, do: "#{exec_line} -S mix app.start", else: exec_line

    spawn fn->
      exec_line |> String.to_charlist |> :os.cmd
    end

    new_meta = Map.put(app.meta, :runner_id, runner_id)
    app = %{app | meta: new_meta}

    {:ok, app}
  end

  def on_exit(app, _opts) do
    runner_id = Map.get(app.meta, :runner_id)
    if runner_id do
      :os.cmd 'pkill -f #{runner_id}'
    end
  end
end


