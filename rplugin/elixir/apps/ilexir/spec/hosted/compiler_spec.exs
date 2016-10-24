defmodule Ilexir.CompilerSpec do
  use ESpec

  before do
    Ilexir.Compiler.start_link
  end

  context "empty module" do
    let :module_name, do: EmptyModule
    let :some_code, do: ~s"""
    defmodule #{module_name} do
    end
    """

    it "pre-saves module __ENV__ after compilation" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
    end
  end

  context "module with func" do
    let :module_name, do: ModuleWithFunc
    let :some_code, do: ~s"""
    defmodule #{module_name} do
      def some_func do
      end
    end
    """

    it "pre-saves module __ENV__ after compilation" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
    end
  end

  context "module with multiple functions" do
    let :module_name, do: ModuleWithMultipleFunc
    let :some_code, do: ~s"""
    defmodule #{module_name} do
      def some_func do
      end

      def some_func2 do
      end
    end
    """

    it "pre-saves module __ENV__ after compilation" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
    end
  end

  context "multiple modules" do
    let :first_module, do: FirstModule
    let :second_module, do: SecondModule
    let :some_code, do: ~s"""
    defmodule #{first_module} do
      def some_func do
      end

      def some_func2 do
      end
    end

    defmodule #{second_module} do
      def some_func do
      end

      def some_func2 do
      end
    end
    """

    it "pre-saves module __ENV__ after compilation for each module" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(first_module)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(first_module).module).to eq(first_module)

      expect(Ilexir.Compiler.get_env(second_module)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(second_module).module).to eq(second_module)
    end
  end
end
