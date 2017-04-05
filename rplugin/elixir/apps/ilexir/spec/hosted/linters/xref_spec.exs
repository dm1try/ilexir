defmodule Ilexir.Linters.XrefSpec do
  use ESpec, async: false

  alias Ilexir.Xref.Server, as: XrefServer
  @file_path "/some/linted_file.ex"

  context "dispatches for exising module are found" do
    @dispatches_with_reachable_mod {%{}, %{Enum => %{{:any?, 1} => [1]}}}

    before do
      allow(XrefServer).to accept(:get_dispatches, fn(@file_path) -> @dispatches_with_reachable_mod end)
    end

    it "returns no fix items" do
      result = Ilexir.Linter.Xref.run(@file_path, "")

      expect(result).to be([])
    end
  end

  context "dispatches for a not exising module are found" do
    @dispatches_with_unreachable_mod {%{},%{SomeUnexistingMod => %{{:any?, 1} => [10]}}}

     before do
       allow(XrefServer).to accept(:get_dispatches, fn(_mod) -> @dispatches_with_unreachable_mod end)
     end

     it "returns fix item for unreachable mod" do
       result = Ilexir.Linter.Xref.run(@file_path, "")

       expect(result).to be_list()

       issue = hd(result)

       expect(issue.type).to eq(:warning)
       expect(issue.file).to eq(@file_path)
       expect(issue.text).to match("Module SomeUnexistingMod is unreachable.")
       expect(issue.location.line).to eq(10)
     end
  end

  context "dispatches for a unexising func in existing mod are found" do
    @dispatches_with_unreachable_func {%{},%{Enum => %{{:any?, 3} => [2]}}}

     before do
       allow(XrefServer).to accept(:get_dispatches, fn(_mod) -> @dispatches_with_unreachable_func end)
     end

     it "returns fix item for unreachable func" do
       result = Ilexir.Linter.Xref.run(@file_path, "")

       expect(result).to be_list()

       issue = hd(result)

       expect(issue.type).to eq(:warning)
       expect(issue.text).to match("function Enum.any?/3 is unreachable.")
       expect(issue.location.line).to eq(2)
     end
  end

  context "unreachable dispatches found in multiple places" do
    @lines [2, 10]
    @dispatches_with_unreachable_func {%{},%{Enum => %{{:any?, 3} => @lines}}}

     before do
       allow(XrefServer).to accept(:get_dispatches, fn(_mod) -> @dispatches_with_unreachable_func end)
     end

     it "returns fix item for unreachable func" do
       result = Ilexir.Linter.Xref.run(@file_path, "")

       expect(result).to be_list()
       expect(result).to have_length(length(@lines))

       issue = hd(result)
       expect(issue.text).to match("function Enum.any?/3 is unreachable.")
     end
  end

  context "short-circuit erlang andalso/orelse functions" do
    @dispatches_with_special_funcs {%{},%{:erlang => %{{:andalso, 2} => [1]}}}

     before do
       allow(XrefServer).to accept(:get_dispatches, fn(_mod) -> @dispatches_with_special_funcs end)
     end

     it "returns no errors" do
       result = Ilexir.Linter.Xref.run(@file_path, "")

       expect(result).to have_length(0)
     end
  end
end
