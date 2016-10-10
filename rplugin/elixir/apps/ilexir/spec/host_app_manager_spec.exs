defmodule Ilexir.HostAppManagerSpec do
  use ESpec, async: false
  alias Ilexir.HostAppManager, as: Manager

  let :app_path, do: Path.expand("#{__DIR__}/fixtures/dummy_mix_app")
  let :file_path, do: Path.expand("#{__DIR__}/fixtures/dummy_mix_app/lib/dummy_mix_app.ex")
  let :app, do: %Ilexir.HostApp{name: "dummy_mix_app"}

  before do
    {:ok, manager} = Manager.start_link
    {:ok, embed_nvim_session} = NVim.Session.Embed.start_link(session_name: NVim.Session)
    {:shared, manager: manager, embed_nvim_session: embed_nvim_session}
  end

  finally do
    GenServer.stop(shared.manager)
    NVim.Session.Embed.stop(shared.embed_nvim_session)
  end

  describe ".add_app_path" do
    it "adds path as available for running app host" do
      expect(Manager.add_app_path(app_path)).to eq(:ok)
    end
  end

  describe ".app_paths" do
    it "returns list of available app host paths" do
      expect(Manager.app_paths()).to eq([])

      Manager.add_app_path(app_path)
      expect(Manager.app_paths()).to eq([app_path])
    end
  end

  describe ".start_app" do
    it "runs the app" do
      {status, app} = Manager.start_app(app_path)
      expect(status).to be(:ok)
      expect(Ilexir.HostApp.running?(app)).to be_truthy
    end
  end

  describe ".lookup" do
    before do
      Manager.start_app(app_path)
      :ok
    end

    it "looks up for a suitable host for a provided file and runs it" do
      {status, app} = Manager.lookup(file_path)
      expect(status).to be(:ok)
      expect(Ilexir.HostApp.running?(app)).to be_truthy
    end
  end

  describe ".running_apps" do
    before do
      Manager.start_app(app_path)
      :ok
    end

    it "returns running apps" do
      expect(length(Manager.running_apps())).to eq(1)
    end
  end

  describe ".stop_all" do
    before do
      Manager.start_app(app_path)
      :ok
    end

    it "stops running apps" do
      expect(length(Manager.running_apps())).to eq(1)

      expect(Manager.stop_all).to eq(:ok)

      expect(length(Manager.running_apps())).to eq(0)
      expect(Ilexir.HostApp.running?(app)).to be_falsy
    end
  end
end
