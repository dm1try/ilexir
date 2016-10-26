defmodule Ilexir.CompilerSpec do
  use ESpec
  alias Ilexir.Compiler

  context "callback injections" do
    before do: Compiler.start_link
    finally do: GenServer.stop(Compiler)

    context "empty module" do
      let :some_code, do: ~s"""
      defmodule EmptyModule do
      end
      """

      it "compiles module" do
        [{mod, _code}] = Compiler.compile_string(some_code, "file.ex")
        expect(mod).to eq(EmptyModule)
      end

      it "saves module env after compilation" do
        Compiler.compile_string(some_code, "file.ex")
        expect(Compiler.get_env(EmptyModule)).not_to eq(nil)
      end
    end

    context "module with func" do
      let :some_code, do: ~s"""
      defmodule ModuleWithFunc do
        def some_func do
        end
      end
      """

      it do: expect(
        Compiler.compile_string(some_code)
      ).to be_truthy
    end

    context "module with multiple functions" do
      let :some_code, do: ~s"""
      defmodule ModuleWithMultipleFunc do
        def some_func do
        end

        def some_func2 do
        end
      end
      """

      it do: expect(
        Compiler.compile_string(some_code)
      ).to be_truthy
    end

    context "multiple modules" do
      let :some_code, do: ~s"""
      defmodule FirstModule do
        def some_func do
        end

        def some_func2 do
        end
      end

      defmodule SecondModule do
        def some_func do
        end

        def some_func2 do
        end
      end
      """

      it do: expect(
        Compiler.compile_string(some_code)
      ).to be_truthy
    end
  end

  context "subscribers" do
    let :module_name, do: TestCallbacks
    let :module_code_string, do: "defmodule #{module_name}, do: :nothing"
    let :filename, do: "some_file.ex"
    let :expected_ast, do: Code.string_to_quoted!(module_code_string)

    finally do
      GenServer.stop(Compiler)
    end

    it "sends :on_ast_processing message to subscriber" do
      {:ok, _pid} = Compiler.start_link(subscribers: %{on_ast_processing: [ESpec.Runner]})
      Compiler.compile_string(module_code_string, filename)

      receive do
        {:on_ast_processing, {file, ast}} ->
          expect(file).to eq(filename)
          expect(ast).to eq(expected_ast)
      after 200 -> raise "ast callback is not received"
      end
    end

    it "sends :after_compile message to subscriber with env and bytecode" do
      {:ok, _pid} = Compiler.start_link(subscribers: %{after_compile: [ESpec.Runner]})
      Compiler.compile_string(module_code_string, filename)

      receive do
        {:after_compile, {env, bytecode}} ->
          expect(env.module).to eq(module_name)
          expect(bytecode).to be_truthy
      after 200 -> raise "after_compile callback is not received"
      end
    end
  end

  context "compile errors" do
    before do: Compiler.start_link
    finally do: GenServer.stop(Compiler)

    it "returns an error" do
      {:error, error} = Compiler.compile_string("undefined + 2")
      expect(error).to be_struct(CompileError)
    end
  end
end
