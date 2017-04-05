defmodule Ilexir.Code.ServerSpec do
  use ESpec
  alias Ilexir.Code.Server, as: CodeServer

  before do
    {:ok, pid} = CodeServer.start_link
    {:shared, pid: pid}
  end

  finally do
    GenServer.stop(shared.pid)
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

  context "all modules succesfully returned", async: false do
    before do
      allow(Ilexir.Code).to accept(:all_modules, fn-> [Kernel, :timer, Atom, Enum] end)
    end

    it "returns modules sorted by name desc" do
      expect(CodeServer.get_modules).to eq([:timer, Kernel, Enum, Atom])
    end
  end

  context "dynamically created module" do
    let :obj_code do
      defmodule Hello do
        @doc "world"
        def world do
          "world"
        end
      end |> elem(2)
    end

    it "allows add modules in runtime" do
      CodeServer.add_module({Hello, obj_code(), "test_file.ex"})

      modules = CodeServer.get_modules()

      expect(modules).to have(Hello)

      docs = CodeServer.get_elixir_docs(Hello, :docs)
      expect_elixir_docs_returned(docs)
    end

    it "updates module info trough compile callback" do
      {:module, mod_name, obj_code, env} = defmodule Dynamic do
        @moduledoc "I'm here"
        __ENV__
      end

      send CodeServer, {:after_compile, {env, obj_code}}
      expect(CodeServer.get_modules()).to have(mod_name)
    end
  end

  context "sources" do
    it "finds modules" do
      {:module, _, obj_code, env} = defmodule IamHere, do: __ENV__
      send CodeServer, {:after_compile, {env, obj_code}}

      expect(CodeServer.get_source(IamHere)).to eq({env.file, env.line})

      {path, line} = CodeServer.get_source(Enum)
      expect(path).to be_bitstring()
      expect(line).to be_number()
    end

    it "finds functions" do
      {path, line} = CodeServer.get_source({Enum, :all?})
      expect(path).to be_bitstring()
      expect(line).to be_number()
    end
  end

  defp expect_elixir_docs_returned(docs) do
    expect(length(docs)).to be(:>, 0)
    first_doc = Enum.at(docs,0)
    expect(elem(first_doc,2)).to eq(:def)
  end
end
