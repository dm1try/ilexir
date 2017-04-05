defmodule Ilexir.Linters.CredoSpec do
  use ESpec

  before do
    {:ok, pid} = Credo.start [], []
    {:shared, credo_pid: pid}
  end

  finally do
    GenServer.stop(shared.credo_pid)
  end

  let :file_name, do: "credo_check_me.ex"
  let :file_content do
    """
    defmodule CredoCheckMe do
    end
    """
  end

  it "returns QuickFix items for founded credo issues" do
    result = Ilexir.Linter.Credo.run(file_name(), file_content())

    expect(result).to be_list()

    issue = hd(result)

    expect(issue.file).to eq(file_name())
    expect(issue.type).to eq(:warning)
    expect(issue.text).to match("moduledoc tag.")
  end
end
