defmodule Ilexir.LinterSpec do
  use ESpec, async: false
  alias Ilexir.{Linter, QuickFix, HostAppManager}
  alias NVim.Session.Embed, as: EmbedSession

  before do
    {:ok, embed_session_pid} = EmbedSession.start_link
    {:ok, quick_fix_pid} = QuickFix.start_link
    {:ok, host_manager_pid} = HostAppManager.start_link
    {:ok, linter_pid} = Linter.start_link
    {:shared, quick_fix_pid: quick_fix_pid, host_manager_pid: host_manager_pid,
     embed_session_pid: embed_session_pid, linter_pid: linter_pid}
  end


  xcontext "some mix app is running" do
    let :runner_id, do: "linter_test"

    before do
      HostAppManager.start_app(Ilexir.Fixtures.test_elixir_mix_project_path,
                               runner_id: runner_id(),
                               callback: fn(app)-> send ESpec.Runner, {:started, app} end)

      app = receive do {:started, app} -> app
      after 5000 -> raise "mix app is not running"
      end

      {:shared, app: app}
    end

    finally do
      HostAppManager.stop_app(shared.app, runner_id: runner_id())
      :ok
    end

    it "runs the linter on hosted app" do
      expect(Linter.check("file", "content", Ilexir.Linter.Dummy, shared.app)).to eq(:ok)
    end
  end

  finally do
    GenServer.stop(shared.quick_fix_pid)
    GenServer.stop(shared.host_manager_pid)
    GenServer.stop(shared.linter_pid)
    EmbedSession.stop(shared.embed_session_pid)
  end
end
