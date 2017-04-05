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

  it "returns object code" do
    expect(Code.get_object_code(Enum)).to be_binary()
    expect(Code.get_object_code(UnknownModule)).to be(nil)
  end

  context "sources" do
    context "elixir module has a compilation info", async: false do
      before do
        allow(Code.Info).to accept :compile_info, fn(ModWithCompileInfo)->
          [options: [:debug_info], version: '7.0', source: '/path/to/kernel.ex']
        end
      end

      it "returns path to the source" do
        expect(Code.get_source_path(ModWithCompileInfo)).to eq("/path/to/kernel.ex")
      end
    end

    context "elixir module without a compilation info", async: false do
      before do
        allow(Code).to accept :compile_info, fn(ModWithoutCompileInfo)-> [] end
      end

      it "returns nil" do
        expect(Code.get_source_path(ModWithoutCompileInfo)).to eq(nil)
      end
    end

    context "actual location" do
      let :current_line, do: __ENV__.line
      let :code do
        {_, _, obj_code, _} = defmodule FuncDefs do
          @doc "This is func 1"
          def func(test), do: test

          @doc "This is func 2"
          def func2, do: 2

          @doc "This is macro"
          defmacro macro1, do: :nothing
        end

        obj_code
      end

      it "finds module source line in object code" do
        expect(Code.find_source_line({:module, Ilexir.CodeSpec.FuncDefs}, code())).to eq(current_line() + 2)
      end

      it "finds functions source line in object code" do
        expect(Code.find_source_line({:function, {:func, 1}}, code())).to eq(current_line() + 4)
        expect(Code.find_source_line({:function, {:func2, 0}}, code())).to eq(current_line() + 7)
        expect(Code.find_source_line({:function, {:macro1, 0}}, code())).to eq(current_line() + 10)
      end

      it "finds functions without provided arity" do
        expect(Code.find_source_line({:function, :func2}, code())).to eq(current_line() + 7)
      end
    end
  end

  describe ".elixir_module?" do
    it "returns true if a module is elixir module" do
      expect(Code.elixir_module?(Atom)).to eq(true)
      expect(Code.elixir_module?(:timer)).to eq(false)
    end
  end

  defp expect_elixir_docs_returned(docs) do
    expect(length(docs)).to be(:>, 0)
    first_doc = Enum.at(docs,0)
    expect(elem(first_doc,2)).to eq(:def)
  end
end
