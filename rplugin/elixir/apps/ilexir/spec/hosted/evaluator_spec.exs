defmodule Ilexir.EvaluatorSpec do
  use ESpec
  alias Ilexir.Evaluator

  before do
    Evaluator.start_link
  end

  finally do
    GenServer.stop(Evaluator)
  end

  describe ".eval_string" do
    let :code_part do
      """
      a = 1
      a + 2
      """
    end

    let :module_name, do: MyModule

    let :some_code, do: ~s"""
    defmodule #{module_name} do
      def some_func do
        #{code_part}
      end
    end
    """

    it "evaluates string" do
      expect(Evaluator.eval_string(code_part)).to eq({:ok, 3})
    end

    context "enviroment is provided" do
      let :code_part do
        """
        E.any?([])
        """
      end

      let :module_name, do: ModuleWithAlias

      let :some_code, do: ~s"""
      defmodule #{module_name} do
        alias Enum, as: E

        def some_func do
          #{code_part}
        end

        def env do
          __ENV__
        end
      end
      """

      before do
        Code.compile_string(some_code)
      end

      it "respects env values on the evaluating" do
        expect(Evaluator.eval_string(code_part, env: ModuleWithAlias.env)).to eq({:ok, false})
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

      let :some_code, do: ~s"""
      defmodule #{module_name} do
        def some_func do
          #{first_code_part}
          #{second_code_part}
        end
      end
      """

      before do
        Code.compile_string(some_code)
        Evaluator.eval_string(first_code_part)
      end

      it "pre-saves and reuse evaluated bindings between evaluations" do
        expect(Evaluator.eval_string(second_code_part)).to eq({:ok, true})
      end
    end

    context "undefined var" do
      let :code_part do
        """
        b + 1
        """
      end

      let :module_name, do: EvalWithUndefined

      let :some_code, do: ~s"""
      defmodule #{module_name} do
        def some_func do
          b = 3
          #{code_part}
        end
      end
      """

      before do
        Code.compile_string(some_code)
      end

      it "returns undefined var name" do
        expect(Evaluator.eval_string(code_part)).to eq({:undefined, "b"})
      end
    end

    context "other compile errors" do
      it "returns error" do
        {status, desc} = Evaluator.eval_string("[] + []")

        expect(status).to eq(:error)
        expect(desc).to have("bad argument")
      end
    end
  end

  context "bindigs management" do
    it "gets/sets/adds bindings" do
      expect(Evaluator.get_bindings()).to eq([])
      expect(Evaluator.set_bindings([a: 1])).to eq([a: 1])
      expect(Evaluator.add_bindings([b: 2])).to eq([a: 1, b: 2])

      expect(Evaluator.eval_string("a + b")).to eq({:ok, 3})
    end
  end
end
