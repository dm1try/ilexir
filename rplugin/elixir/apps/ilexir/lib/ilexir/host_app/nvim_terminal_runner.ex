defmodule Ilexir.HostApp.NvimTerminalRunner do
  alias Ilexir.HostApp, as: App

  @behaviour App.Runner

  def start_app(%App{path: path, exec_path: exec_path, remote_name: remote_name} = app, opts) do
    nvim_session = Keyword.get(opts, :nvim_session) || raise "nvim_session is required"

    nvim_session.nvim_command("bot new|res 8|set wfh|terminal")

    {:ok, current_window} = nvim_session.nvim_get_current_win()
    nvim_session.nvim_win_set_var(current_window, "ilexir_app", remote_name)

    nvim_session.nvim_feedkeys("cd #{path}\n", "i", false)
    nvim_session.nvim_feedkeys("#{exec_path}\n", "i", false)
    nvim_session.nvim_command("stopinsert | wincmd p")

    {:ok, app}
  end

  def on_exit(app, _opts) do
    # do nothing atm
    {:ok, app}
  end
end


