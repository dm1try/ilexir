Code.require_file "hosted/ilexir/standard_error_stub.ex"

defmodule Ilexir.StandardErrorStubSpec do
  use ESpec

  alias Ilexir.StandardErrorStub

  before do
    StandardErrorStub.start_link
  end

  it "caches warnings that are sent to standard error" do
    no_warnings = StandardErrorStub.with_stab_standard_error fn->
      "no warnings here"
    end

    expect(no_warnings).to eq([])

    warnings = StandardErrorStub.with_stab_standard_error fn->
      IO.warn "some warning here"
    end

    expect(warnings).not_to be_empty
    expect(hd(warnings).text).to eq "some warning here"
  end
end
