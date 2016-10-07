defmodule Ilexir.HostAppSpec do
  use ESpec, async: false
  alias Ilexir.HostApp

  @nvim_session_name NVim.AppRunnerSession

  let_ok :local_hostname, do: :inet.gethostname

  before do
    Node.start :host_app_test, :shortnames
  end

  describe ".remote_name" do
    let :app, do: %HostApp{name: "some_app", env: "dev"}

    it "returns remote name based on app name and env values" do
      expect(HostApp.remote_name(app)).to eq(:"some_app_dev@#{local_hostname}")
    end
  end

  context "stand-alone elixir file without project" do
    let :app_path, do: Path.expand("#{__DIR__}/fixtures")
    let :expected_app, do: %HostApp{name: "fixtures", env: "dev", path: app_path}
    let :node_name, do: HostApp.remote_name(expected_app)

    before do
     {:ok, pid} = NVim.Test.Session.Embed.start_link(session_name: @nvim_session_name)
     {:shared, embed_pid: pid}
    end

    finally do
      NVim.Test.Session.Embed.stop(shared.embed_pid)
    end

    it "starts the app host which ready for remote calls" do
      {status, returned_app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      expect(status).to eq(:ok)
      expect(returned_app.name).to eq(expected_app.name)

      expect(:rpc.call(node_name, Code, :eval_string, ["1+1"])).to eq({2, []})
    end

    it "stops the app host" do
      {:ok, app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      expect(HostApp.stop(app)).to eq(:ok)
    end

    it "checks running status of the app host" do
      {:ok, app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      expect(HostApp.running?(app)).to be_truthy
    end

    it "loads file on the app host" do
      {:ok, app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      [{mod, _code}] = HostApp.load_file(app, Ilexir.Fixtures.test_elixir_file_path)
      expect(mod).to eq Ilexir.Fixtures.TestModule
    end

    it "compiles string on the app host" do
      {:ok, app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      [{mod, _code}] = HostApp.compile_string(app, """
        defmodule ExpectedModule do
          def some_code do
          end
        end
      """, "some_file.ex")
      expect(mod).to eq ExpectedModule
    end

    context "the app succesfully started and some file compiled" do
      let_ok :app, do: HostApp.start(app_path, [], nvim_session: @nvim_session_name)
      let :filename, do: "compiled_file.ex"
      let :compiled_line, do: "1 + 1"
      let :expected_result, do: 2
      let :line_number, do: 3
      let :file_content do
        """
        defmodule ExpectedModule do
          def some_method do
            #{compiled_line}
          end
        end
        """
      end

      before do
        HostApp.compile_string(app, file_content, filename)
      end

      it "evals string on the app host for previously compiled file" do
        {status, result} = HostApp.eval_string(app, compiled_line, filename, 2)

        expect(status).to eq(:ok)
        expect(result).to eq(expected_result)
      end
    end

    it "calls method on the app" do
      {:ok, app} = HostApp.start(app_path, [], nvim_session: @nvim_session_name)

      result = HostApp.call(app, String, :to_atom, ["atom"])
      expect(result).to eq :atom
    end
  end

  context "Mix project" do
    let :app_path, do: Path.expand("#{__DIR__}/fixtures/dummy_mix_app")
    let :app, do: %HostApp{name: "dummy_mix_app"}
    let :node_name, do: HostApp.remote_name(app)

    before do
     {:ok, pid} = NVim.Test.Session.Embed.start_link(session_name: @nvim_session_name)
     {:shared, embed_pid: pid}
    end

    finally do
      NVim.Test.Session.Embed.stop(shared.embed_pid)
    end

    it "starts the host and loads Mix application" do
      HostApp.start(app_path, [], nvim_session: @nvim_session_name)
      result = :rpc.call(node_name, DummyMixApp, :hello, [])
      expect(result).to eq("world")
    end
  end
end
