defmodule Ilexir.CodeSpec do
  use ESpec
  alias Ilexir.Code

  it "returns elixir docs for module" do
    docs = Code.get_elixir_docs(Enum, :docs)
    expect_elixir_docs_returned(docs)
  end

  it "returns elixir docs if object code is provided" do
    {_, _, obj_code, _} = defmodule Mod, do: @moduledoc "the module doc"
    {_line, doc} = Code.get_elixir_docs(obj_code, :moduledoc)
    expect(doc).to eq("the module doc")
  end

  it "returns all available modules" do
    modules = Code.all_modules()
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
