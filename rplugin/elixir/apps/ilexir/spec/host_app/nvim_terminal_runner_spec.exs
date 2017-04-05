defmodule Ilexir.HostApp.NvimTerminalRunnerSpec do
  use ESpec
  alias Ilexir.HostApp.NvimTerminalRunner, as: Runner
  alias Ilexir.HostApp, as: App

  @nvim_session_name TerminalRunnerTest

  let :mix_app, do: App.build(Path.expand("spec/fixtures/dummy_mix_app"))
  let :options, do: [nvim_session: @nvim_session_name]

  before do
    {:ok, pid} = NVim.Session.Embed.start_link(session_name: @nvim_session_name)
    {:shared, embed_pid: pid}
  end

  finally do
    NVim.Session.Embed.stop(shared.embed_pid)
  end

  it "starts the app" do
    expect(Runner.start_app(mix_app(), options())).to eq({:ok, mix_app()})
  end

  context "with term option" do
    let :options, do: [nvim_session: @nvim_session_name, term: true]

    it "starts the app in terminal window" do
      expect(Runner.start_app(mix_app(), options())).to eq({:ok, mix_app()})
      expect_it_marks_nvim_window()
      # expect_it_actually_run_node
    end
  end

  defp expect_it_marks_nvim_window do
    {:ok, windows} = @nvim_session_name.nvim_list_wins()

    var = Enum.find_value(windows, fn(win)->
      case @nvim_session_name.nvim_win_get_var(win, "ilexir_app") do
        {:ok, ilexir_app_var} ->
          ilexir_app_var
        _ ->
          nil
      end
    end)

    expect(var).to eq(to_string(mix_app().remote_name))
  end
end
