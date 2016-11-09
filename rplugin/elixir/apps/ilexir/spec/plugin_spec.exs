defmodule Ilexir.PluginSpec do
  use ESpec, async: false

  alias Ilexir.{HostAppManager, HostApp}
  import Ilexir.Plugin, only: [handle_rpc_method: 3]

  @app_path "fixtures"
  @app_id 1
  @app %HostApp{id: @app_id}

  before do
    {:ok, plugin_id} = Ilexir.Plugin.start_link()
    {:shared, plugin_id: plugin_id}
  end

  finally do
    GenServer.stop(shared.plugin_id)
  end

  before do
    allow(NVim.Session).to accept(:nvim_call_function, fn("getcwd",_)-> {:ok, @app_path} end)

    allow(HostAppManager).to accept(:start_app, fn(_,_)-> {:ok, @app} end)
    allow(HostAppManager).to accept(:get_app, fn(@app_id)-> {:ok, @app} end)
    allow(HostAppManager).to accept(:stop_app)

    allow(NVim.Session).to accept(:vim_command)
  end

  it "reuse last running application id for consequent commands" do
    handle_rpc_method("command", "IlexirStartInWorkingDir", [[]])
    handle_rpc_method("command", "IlexirStopApp", [])

    expect(HostAppManager).to accepted(:stop_app, [@app])
  end
end
