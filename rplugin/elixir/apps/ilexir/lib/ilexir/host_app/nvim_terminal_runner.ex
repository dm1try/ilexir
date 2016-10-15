defmodule Ilexir.HostApp.NvimTerminalRunner do
  def start_app(%Ilexir.HostApp{path: path, mix_app?: mix_app?} = app, opts) do
    nvim_session = Keyword.get(opts, :nvim_session) || raise "nvim_session is required"

    remote_name = Ilexir.HostApp.remote_name(app)

    exec_line = "cd #{path} && elixir --no-halt --sname #{remote_name}"
    exec_line = if mix_app?, do: "#{exec_line} -S mix app.start", else: exec_line

    command = "new | call termopen('#{exec_line}') | silent file #{remote_name} | hide"
    nvim_session.vim_command(command)
    {:ok, app}
  end

  def stop_app(app, opts) do
    nvim_session = Keyword.get(opts, :nvim_session) || raise "nvim_session is required"

    remote_name = Ilexir.HostApp.remote_name(app)

    {:ok, buffers} = nvim_session.nvim_list_bufs()

    buffer_name = Enum.find_value(buffers, fn(buffer)->
      {:ok, buffer_name} = nvim_session.nvim_buf_get_name(buffer)
      String.contains?(buffer_name,to_string(remote_name)) && buffer_name
    end)

    if buffer_name do
      nvim_session.nvim_command("bdelete! #{buffer_name}")

      {:ok, app}
    else
      {:error, "application buffer is not found"}
    end
  end
end
