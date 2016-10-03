defmodule Ilexir.HostApp.NvimTerminalRunner do
  def start_app(%Ilexir.HostApp{path: path, mix_app?: mix_app?} = app, opts) do
    nvim_session = Keyword.get(opts, :nvim_session) || raise "nvim_session is required"

    remote_name = Ilexir.HostApp.remote_name(app)

    exec_line = "cd #{path} && elixir --no-halt --sname #{remote_name}"
    exec_line = if mix_app?, do: "#{exec_line} -S mix app.start", else: exec_line

    command = "new | call termopen('#{exec_line}') | set noma | hide"
    nvim_session.vim_command(command)
    {:ok, app}
  end
end
