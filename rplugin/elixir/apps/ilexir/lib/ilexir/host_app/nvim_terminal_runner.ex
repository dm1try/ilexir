defmodule Ilexir.HostApp.NvimTerminalRunner do
  alias Ilexir.HostApp, as: App
  require Logger
  @behaviour App.Runner

  def start_app(%App{path: path, exec_path: exec_path, remote_name: remote_name} = app, opts) do
    nvim_session = Keyword.get(opts, :nvim_session) || raise "nvim_session is required"
    shell_command = "cd #{path} && #{exec_path}"

    if opts[:term] do
      run_in_term(nvim_session, shell_command, remote_name)
    else
      run_in_job(nvim_session, shell_command)
    end

    {:ok, app}
  end

  def on_exit(app, _opts) do
    # do nothing atm
    {:ok, app}
  end

  defp run_in_job(nvim_session, shell_command) do
    case nvim_session.nvim_call_function("jobstart", [shell_command]) do
      {:ok, _} -> Logger.info("running #{shell_command}")
      error -> Logger.error("problem with running: #{shell_command}")
    end
  end

  defp run_in_term(nvim_session, shell_command, remote_name) do
    nvim_session.nvim_command("bot new|res 8|set wfh|terminal")

    {:ok, current_window} = nvim_session.nvim_get_current_win()
    nvim_session.nvim_win_set_var(current_window, "ilexir_app", remote_name)

    nvim_session.nvim_feedkeys("\n#{shell_command}\n", "i", false)
    nvim_session.nvim_command("stopinsert | wincmd p")
  end
end


