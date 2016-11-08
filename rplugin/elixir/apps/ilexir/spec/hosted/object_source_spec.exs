defmodule Ilexir.ObjectSourceSpec do
  use ESpec
  alias Ilexir.ObjectSource

  let :line, do: "empty? = Enum.any?([])"

  context "cursor on module name" do
    let :current_column, do: 11

    it "returns module" do
      expect(ObjectSource.find_object(line, current_column)).to eq({:module, Enum})
    end
  end

  context "cursor on function name" do
    let :current_column, do: 14

    it "returns module with function arity" do
      expect(ObjectSource.find_object(line, current_column)).to eq({:function, {Enum, :any?}})
    end
  end

  context "erlang module" do
    let :line, do: ":timer.sleep(500)"

    context "cursor on module name" do
      let :current_column, do: 2

      it "returns module" do
        expect(ObjectSource.find_object(line, current_column)).to eq({:erlang_module, :timer})
      end
    end

    context "cursor on func" do
      let :current_column, do: 9

      it "returns module" do
        expect(ObjectSource.find_object(line, current_column)).to eq({:function, {:timer, :sleep}})
      end

      context "without parentensis" do
        let :line, do: ":timer.sleep 500"

        it "returns module" do
          expect(ObjectSource.find_object(line, current_column)).to eq({:function, {:timer, :sleep}})
        end
      end
    end

    context "compound mod" do
      let :line, do: "All.MyMod.Enum.Super.Kernel"
      let :current_column, do: 24

      it "returns module" do
        expect(ObjectSource.find_object(line, current_column)).to eq({:module, All.MyMod.Enum.Super.Kernel})
      end

      context "cursor on the second part" do
        let :current_column, do: 5

        it "returns left-most module" do
          expect(ObjectSource.find_object(line, current_column)).to eq({:module, All.MyMod})
        end
      end
    end

    context "with brackets :)" do
      let :line, do: "a = [All.MyMod.read, some_a]"

      it "returns sources" do
        expect(ObjectSource.find_object(line, 10)).to eq({:module, All.MyMod})
        expect(ObjectSource.find_object(line, 15)).to eq({:function, {All.MyMod, :read}})
      end
    end
  end

  context "with custom env" do
    let :env do
      {_, _, _, env} = defmodule CustomEnv do
        alias Enum, as: E
        import File
        E.any?([])
        read("")
        __ENV__
      end

      env
    end

    context "cursor on aliased module" do
      let :line, do: "   E.any?([])  "
      let :current_column, do: 3

      it "returns actual module" do
        expect(ObjectSource.find_object(line, current_column, env: env)).to eq({:module, Enum})
      end
    end

    context "cursor on imported function" do
      let :line, do: "file = read(file_path)"
      let :current_column, do: 9

      it "returns actual module" do
        expect(ObjectSource.find_object(line, current_column, env: env)).to eq({:function, {File, :read}})
      end
    end

    context "the call in square brackets" do
      let :line, do: "res = [read(file_path), 0]"
      let :current_column, do: 9

      it "returns actual module" do

        expect(ObjectSource.find_object(line, current_column, env: env)).to eq({:function, {File, :read}})
      end
    end
  end
end

