defmodule Ilexir.CompilerSpec do
  use ESpec

  before do
    Ilexir.Compiler.start_link
  end

  context "empty module" do
    let :module_name, do: EmptyModule
    let :some_code do
      """
      defmodule #{module_name} do
      end
      """
  end

  it "pre-saves module __ENV__ after compilation" do
    Ilexir.Compiler.compile_string(some_code)

    expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
    expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
  end
end

context "module with func" do
  let :module_name, do: ModuleWithFunc
  let :some_code do
    """
    defmodule #{module_name} do
    def some_func do
    end
    end
    """
    end

    it "pre-saves module __ENV__ after compilation" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
    end
  end

  context "module with multiple functions" do
    let :module_name, do: ModuleWithMultipleFunc
    let :some_code do
      """
      defmodule #{module_name} do
      def some_func do
      end

      def some_func2 do
      end
      end
      """
    end

    it "pre-saves module __ENV__ after compilation" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(module_name)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(module_name).module).to eq(module_name)
    end
  end

  context "multiple modules" do
    let :first_module, do: FirstModule
    let :second_module, do: SecondModule
    let :some_code do
      """
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
    end

    it "pre-saves module __ENV__ after compilation for each module" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.get_env(first_module)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(first_module).module).to eq(first_module)

      expect(Ilexir.Compiler.get_env(second_module)).to_not eq(nil)
      expect(Ilexir.Compiler.get_env(second_module).module).to eq(second_module)
    end
  end

  describe ".eval_string" do
    let :code_part do
      """
      a = 1
      a + 2
      """
    end

    let :module_name, do: MyModule
    let :some_code do
      """
      defmodule #{module_name} do
      def some_func do
      #{code_part}
      end
      end
      """
    end

    it "evaluates string" do
      Ilexir.Compiler.compile_string(some_code)

      expect(Ilexir.Compiler.eval_string(code_part, module_name)).to eq({:ok, 3})
    end

    context "enviroment with aliases" do
      let :code_part do
        """
        E.any?([])
        """
      end

      let :module_name, do: ModuleWithAlias
      let :some_code do
        """
        defmodule #{module_name} do
        alias Enum, as: E

        def some_func do
        #{code_part}
        end
        end
        """
      end

      it "respects env values while evaluating" do
        Ilexir.Compiler.compile_string(some_code)

        expect(Ilexir.Compiler.eval_string(code_part, module_name)).to eq({:ok, false})
      end
    end

    context "multiple sequintial evals" do
      let :first_code_part do
        """
        a = [1, 2, 3]
        """
      end

      let :second_code_part do
        """
        Enum.any?(a)
        """
      end

      let :module_name, do: MultipleEvals
      let :some_code do
        """
        defmodule #{module_name} do
        def some_func do
        #{first_code_part}
        #{second_code_part}
        end
        end
        """
      end

      before do
        Ilexir.Compiler.compile_string(some_code)
        Ilexir.Compiler.eval_string(first_code_part, module_name)
      end

      it "pre-saves and reuse evaluated bindings between evaluations" do
        expect(Ilexir.Compiler.eval_string(second_code_part, module_name)).to eq({:ok, true})
      end
    end

    context "undefined var" do
      let :code_part do
        """
        b + 1
        """
      end

      let :module_name, do: EvalWithUndefined
      let :some_code do
        """
        defmodule #{module_name} do
        def some_func do
        b = 3
        #{code_part}
        end
        end
        """
      end

      before do
        Ilexir.Compiler.compile_string(some_code)
      end

      it "returns undefined var name" do
        expect(Ilexir.Compiler.eval_string(code_part, module_name)).to eq({:undefined, "b"})
      end
    end

    context "multiple modules" do
      let :module_name, do: EvalWithMultipleModules
      let :file_name, do: "test_evaluation.ex"
      let :eval_line, do: "En.any?([])"
      let :eval_line_number, do: 10
      let :some_code do
        """
        defmodule #{module_name} do
          def some_func do
            "some"
          end

          defmodule Inner do
            alias Enum, as: En

            def have_any? do
            #{eval_line}
            end
          end

          defmodule Inner2 do
            def have_any? do
            end

            defmodule Inner3 do
            end
          end
        end
        """
      end

      before do
        Ilexir.Compiler.compile_string(some_code, file_name)
      end

      it "evalutes string in context of related module" do
        expect(
          Ilexir.Compiler.eval_string(eval_line, file_name, 10)
        ).to eq({:ok, false})
      end
    end
  end
end
