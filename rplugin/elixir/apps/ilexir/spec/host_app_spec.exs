defmodule Ilexir.HostAppSpec do
  use ESpec, async: false
  alias Ilexir.HostApp

  let_ok :local_hostname, do: :inet.gethostname

  describe ".build" do
    let :app_path, do: Path.expand("spec/fixtures/dummy_mix_app")

    it "sets name based on appplication path" do
      app = HostApp.build(app_path)
      expect(app.name).to eq("dummy_mix_app")
    end

    it "sets remote name based on app name and env values" do
      app = HostApp.build(app_path, env: :test)
      expect(app.remote_name).to eq(:"dummy_mix_app_test@#{local_hostname}")
    end

    context "exec path for mix app" do
      let :app, do: HostApp.build(app_path, env: :test)

      it "includes default mix command for start the application" do
        expect(app.exec_path).to have("-S mix run")
      end

      it "includes MIX_ENV" do
        expect(app.exec_path).to have("MIX_ENV=test")
      end

      context "custom script command" do
        let :app, do: HostApp.build(app_path, script: "custom.server")

        it "overiddes default script command" do
          expect(app.exec_path).not_to have("app.start")
          expect(app.exec_path).to have("custom.server")
        end
      end
    end

    context "prodided path is mix application" do
      let :app_path, do: Path.expand("spec/fixtures/dummy_mix_app")

      it "marks app as Mix app" do
        app = HostApp.build(app_path)
        expect(app.mix_app?).to eq(true)
      end
    end
  end

  describe ".lookup" do
    let :apps, do: []

    it "returns nil if no running apps" do
      app = HostApp.lookup("some_file.ex", apps)
      expect(app).to eq(nil)
    end

    context "app path includes file for looking up" do
      let :app_path, do: Path.expand("spec/fixtures/dummy_mix_app")
      let :file_path, do: "#{app_path}/dummy_mix_app.ex"
      let :app, do: HostApp.build(app_path)

      it "returns app" do
        founded_app = HostApp.lookup(file_path, [app])
        expect(founded_app).to eq(app)
      end

      context "file path is inside test directory" do
        let :file_path, do: "#{app_path}/spec/some_file_spec.exs"
        let :app_with_test_env, do: HostApp.build(app_path, env: "test")

        it "returns only app with test env" do
          expect(HostApp.lookup(file_path, [app])).to eq(nil)
          expect(HostApp.lookup(file_path, [app_with_test_env])).to eq(app_with_test_env)
          expect(HostApp.lookup(file_path, [app, app_with_test_env])).to eq(app_with_test_env)
        end
      end
    end
  end
end
