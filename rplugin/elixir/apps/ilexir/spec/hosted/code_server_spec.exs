defmodule Ilexir.CodeServerSpec do
  use ESpec
  alias Ilexir.CodeServer

  before do
    CodeServer.start_link
  end

  it "returns elixir docs" do
    docs = CodeServer.get_elixir_docs(Enum, :docs)
    expect_elixir_docs_returned(docs)
  end

  it "returns docs on consequent requests" do
    CodeServer.get_elixir_docs(Enum, :docs)
    docs = CodeServer.get_elixir_docs(Enum, :docs)
    expect_elixir_docs_returned(docs)
  end

  it "returns all available modules" do
    modules = CodeServer.get_modules()

    expect(modules).to have(Kernel)
    expect(modules).to have(:erlang)
    expect(modules).to have(__MODULE__)
  end

  defp expect_elixir_docs_returned(docs) do
    expect(length(docs)).to be(:>, 0)
    first_doc = Enum.at(docs,0)
    expect(elem(first_doc,2)).to eq(:def)
  end
end
