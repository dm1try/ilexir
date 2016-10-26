defmodule Ilexir.HostAppManagerSpec do
  use ESpec, async: false

  alias Ilexir.HostAppManager, as: Manager
  alias Ilexir.HostApp, as: App

  @tmp_dir Path.expand("#{__DIR__}/../tmp")
  @dummy_app_dir Path.expand("#{__DIR__}/fixtures/dummy_mix_app")

  describe "starts and stops hosted applications" do
    before do
      {:ok, manager} = Manager.start_link

      runner_id = "#{Enum.shuffle(97..112)}"

      app_path = Path.join([@tmp_dir, "dummy_mix_app_#{runner_id}"])
      File.mkdir_p!(app_path)
      File.cp_r!(@dummy_app_dir,app_path)

      {:shared, manager: manager,
       runner_opts: [runner_id: runner_id, app_name: "dummy_mix_app"],
       app_path: app_path}
    end

    finally do
      File.rm_rf!(shared.app_path)
      GenServer.stop(shared.manager)
    end

    context "with caller callback" do
      let :client_callback, do: fn(app)-> send ESpec.Runner, app.status end
      let :start_opts, do:  [callback: client_callback] ++ shared.runner_opts

      it "calls callbacks when app ready or fully stopped" do
        {status, app} = Manager.start_app(shared.app_path, start_opts)

        expect(status).to eq(:ok)

        receive do :running -> :ok
        after 5000 -> raise "Start allback is not received" end

        expect(App.call(app, Code, :eval_string, ["1+1"])).to eq({2,[]})
        expect(App.call(app, DummyMixApp, :hello, [])).to eq("world")

        {status, _app} = Manager.stop_app(app)
        expect(status).to eq(:ok)

        receive do :down -> :ok
        after 5000 -> raise "Stop callback is not received" end
      end
    end
  end

  context "with running app" do
    before do
      {:ok, manager} = Manager.start_link

      runner_id = "#{Enum.shuffle(97..112)}"
      app_path = Path.join([@tmp_dir, "eapp_#{runner_id}"])

      File.mkdir_p!(app_path)

      app = bootstrap_running_app(app_path, [runner_id: runner_id])

      {:shared, manager: manager, app: app, app_path: app_path}
    end

    let :file_path, do: "#{shared.app_path}/dummy_mod.ex"

    finally do
      Manager.stop_app(shared.app)
      receive do {:ok, %{status: :down}} -> :ok
      after 5000 -> raise "problem with stopping an app" end

      File.rm_rf!(shared.app_path)
      GenServer.stop(shared.manager)
    end

    it "looks up for a suitable host for a provided file and runs it" do
      {status, app} = Manager.lookup(file_path)
      expect(status).to be(:ok)
      expect(app.status).to be(:running)
    end

    it "returns running apps" do
      expect(length(Manager.running_apps())).to eq(1)
    end

    it "returns error if the same app already started" do
      expect(Manager.start_app(shared.app.path)).to eq({:error, :already_started})
    end
  end

  defp bootstrap_running_app(app_path, opts) do
    opts = opts ++ [callback: fn(app)-> send ESpec.Runner, {:ok, app} end]
    {:ok, %{status: :loading}} = Manager.start_app(app_path, opts)
    receive do {:ok, app} -> app
    after 5000 -> raise "problem with bootstrapping an app" end
  end
end

