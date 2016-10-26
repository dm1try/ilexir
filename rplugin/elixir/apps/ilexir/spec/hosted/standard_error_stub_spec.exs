defmodule Ilexir.StandardErrorStubSpec do
  use ESpec

  alias Ilexir.StandardErrorStub
  import Ilexir.StandardErrorStub

  before do
    StandardErrorStub.start_link
  end

  it "caches warnings that are sent to standard error" do
    no_warnings_result = with_stab_standard_error fn-> "no warnings here" end
    expect(no_warnings_result).to eq("no warnings here")
    expect(warnings()).to eq([])

    result = with_stab_standard_error fn-> IO.warn("some warning here") end

    expect(result).to eq(:ok)
    expect(warnings).not_to be_empty
    expect(hd(warnings).text).to eq "some warning here"
  end
end
