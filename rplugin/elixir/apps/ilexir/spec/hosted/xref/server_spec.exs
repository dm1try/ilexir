defmodule Ilexir.Xref.ServerSpec do
  use ESpec

  alias Ilexir.Xref.Server, as: XrefServer

  before do
    XrefServer.start_link
  end

  finally do
    GenServer.stop(XrefServer)
  end

  it "updates dispatch information on after compile callback" do
    defmodule MyCollection do
      def empty?(params) do
        !Enum.any?(params)
      end

      send XrefServer, {:after_compile, {__ENV__, nil}}
    end

    {_, runtime} = XrefServer.get_dispatches(__ENV__.file)
    expect(runtime).to have_key(Enum)
  end
end
