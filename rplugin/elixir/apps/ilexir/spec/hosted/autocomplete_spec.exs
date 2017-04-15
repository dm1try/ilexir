defmodule Ilexir.Autocomplete.OmniFuncSpec do
  use ESpec

  alias Ilexir.Code.Server, as: CodeServer
  alias Ilexir.Autocomplete.OmniFunc, as: Autocomplete

  import Ilexir.Test.Autocomplete.Assertions

  let :line, do: ""
  let :base, do: ""
  let :current_column, do: 0
  let :line_after_finding, do: (if base() !="", do: String.replace(line(), base(), ""), else: line())
  let :current_column_after_finding, do: current_column() - String.length(base())

  before do
    {:ok, pid} = CodeServer.start_link
    {:shared, code_server_pid: pid}
  end

  finally do
    GenServer.stop(shared.code_server_pid)
  end

  context "empty line" do
    let :line, do: "     "
    let :current_column, do: 3

    it do: expect(
      Autocomplete.find_complete_position(line(), current_column())
    ).to eq(current_column_after_finding())

    it "expands available Elixir modules" do
      results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())

      expect(results).to have_completed_item("Kernel")
    end
  end

  context "some Elixir module" do
    let :line, do: "  Enu"
    let :base, do: "Enu"
    let :current_column, do: 5

    it do: expect(
      Autocomplete.find_complete_position(line(), current_column())
    ).to eq(current_column_after_finding())

    it "expands suitable modules" do
      results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())

      expect(results).to have_completed_item("Enum")
      expect(results).to have_completed_item("Enumerable")

      expect(results).not_to have_completed_item("Kernel")
    end

    context "Elixir remote function call" do
      let :line, do: "  Enum.an "
      let :base, do: "an"
      let :current_column, do: 9

      it do: expect(
        Autocomplete.find_complete_position(line(), current_column())
      ).to eq(current_column_after_finding())

      it do: expect(
        Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
      ).to have_completed_item("any?")

      context "with empty base" do
        let :line, do: "  Enum."
        let :base, do: ""
        let :current_column, do: 7

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "expands available functions" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to have_completed_item("all?")
        end

        it "expands nested modules" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to have_completed_item("EmptyError")
        end
      end

      context "nested module as base" do
        let :line, do: "String.Ch"
        let :base, do: "Ch"
        let :current_column, do: 9

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "expands available nested modules" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())

          expect(results).to have_completed_item("Chars")
        end
      end

      context "functions prefixed with underscores(for internal use)" do
        let :line, do: "Enum.EmptyError.__"
        let :base, do: "__"
        let :current_column, do: 18

        it "does not expand internal functions" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to_not have_completed_item("__struct__")
        end
      end

      context "expand macros" do
        let :line, do: "Bitwise."
        let :base, do: ""
        let :current_column, do: 8

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "expands available nested modules" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())

          expect(results).to have_completed_item("bnot")
        end
      end
    end

    context "erlang module" do
      let :line, do: " :erlan"
      let :base, do: "erlan"
      let :current_column, do: 7

      it do: expect(
        Autocomplete.find_complete_position(line(), current_column())
      ).to eq(current_column_after_finding())

      it do: expect(
        Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
      ).to have_completed_item("erlang")

      context "with starting colon symbol" do
        let :line, do: " :"
        let :base, do: ""
        let :current_column, do: 2

        it do: expect(
          Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
        ).to have_completed_item("timer")
      end
    end

    context "erlang remote function call" do
      let :line, do: "  :timer.sl "
      let :base, do: "sl"
      let :current_column, do: 11

      it do: expect(
        Autocomplete.find_complete_position(line(), current_column())
      ).to eq(current_column_after_finding())

      it "expands available" do
        results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
        expect(results).to have_completed_item("sleep")
      end

      context "with empty base" do
        let :line, do: "  :timer."
        let :base, do: ""
        let :current_column, do: 9

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "expands available" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to have_completed_item("sleep")
        end
      end

      context "erlang.decode_packet" do
        let :line, do: ":erlang."
        let :base, do: ""
        let :current_column, do: 8

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "expands available" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to have_completed_item("decode_packet")
        end
      end

      context "abbreviation format" do
        let :line, do: ":erlang.atom_to_binar"
        let :base, do: "atom_to_binar"
        let :current_column, do: 21

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "includes params" do
          [%{abbr: abbr}] = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(abbr).to eq("atom_to_binary(atom, encoding)")
        end
      end

      context "multiple heads" do
        let :line, do: ":erlang.statistics"
        let :base, do: "statistics"
        let :current_column, do: 18
        let :expected_function_heads, do: 14

        it do: expect(
          Autocomplete.find_complete_position(line(), current_column())
        ).to eq(current_column_after_finding())

        it "includes all available functions heads" do
          results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base())
          expect(results).to have_length(expected_function_heads())
        end
      end
    end
  end

  context "module enviroment(__ENV__) is provided" do
    defmodule SomeModule do
      import List, only: [duplicate: 2]
      import Logger, only: [warn: 1]
      alias Enum, as: En
      alias :timer, as: MyTimer

      def use_all do
        warn "unused duplicate"
        En.any?([])
        duplicate([], [])
        MyTimer.sleep 500
      end

      def module_env do
        __ENV__
      end
    end
    let :env, do: SomeModule.module_env
    let :line, do: "  "
    let :base, do: ""
    let :current_column, do: 2

    it do: expect(
      Autocomplete.find_complete_position(line(), current_column())
    ).to eq(current_column_after_finding())

    it "expands imported functions and macros" do
      results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())

      expect(results).to have_completed_item("duplicate")
      expect(results).to have_completed_item("warn")
    end

    it "expands aliased modules" do
      results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())

      expect(results).to have_completed_item("En")
      expect(results).to have_completed_item("MyTimer")
    end

    context "type format" do
      let :line, do: "MyTimer"
      let :base, do: "MyTimer"
      let :current_column, do: 0

      it "includes original module" do
        [%{type: type}] = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())
        expect(type).to have(":timer")
      end
    end

    context do
      let :line, do: "  MyTime"
      let :base, do: "MyTime"
      let :current_column, do: 8

      it "expands aliased modules" do
        results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())
        expect(results).to have_completed_item("MyTimer")
        expect(results).not_to have_completed_item("En")
      end
    end

    context "aliased Elixir mod" do
      let :line, do: "  En.an"
      let :base, do: "an"
      let :current_column, do: 7

      it do: expect(
        Autocomplete.find_complete_position(line(), current_column())
      ).to eq(current_column_after_finding())

      it "expands imported functions and macros" do
        results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())

        expect(results).to have_completed_item("any?")
      end
    end

    context "aliased erlang mod" do
      let :line, do: "  MyTimer.slee"
      let :base, do: "slee"
      let :current_column, do: 14

      it do: expect(
        Autocomplete.find_complete_position(line(), current_column())
      ).to eq(current_column_after_finding())

      it "expands imported functions and macros" do
        results = Autocomplete.expand(line_after_finding(), current_column_after_finding(), base(), env: env())

        expect(results).to have_completed_item("sleep")
      end
    end
  end
end
