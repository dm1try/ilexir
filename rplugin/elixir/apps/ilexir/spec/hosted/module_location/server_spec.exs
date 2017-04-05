defmodule Ilexir.ModuleLocation.ServerSpec do
  use ESpec

  alias Ilexir.ModuleLocation.Server

  before do
    {:ok, pid} = Server.start_link
    {:shared, pid: pid}
  end

  finally do
    GenServer.stop(shared.pid)
  end

  context "ast for some module was received through a callback" do
    let :module_name, do: TestLocationModule
    let :ast do
      Code.string_to_quoted! """
      defmodule #{module_name()} do
      end
      """
    end

    before do
      send shared.pid, {:on_ast_processing, {"some_file.ex", ast()}}
    end

    it "finds suitable module" do
      expect(Server.get_module("some_file.ex", 1)).to eq(TestLocationModule)
    end
  end
end

