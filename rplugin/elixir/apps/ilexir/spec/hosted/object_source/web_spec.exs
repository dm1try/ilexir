defmodule Ilexir.ObjectSource.WebSpec do
  use ESpec
  import Ilexir.ObjectSource.Web

  context "elixir module docs" do
    let :source, do: {:module, ESpec}
    let :module_version, do: Application.spec(:espec)[:vsn] |> to_string
    let :expected_url, do: "https://hexdocs.pm/espec/#{module_version}/ESpec.html"

    it "returns hexdocs.pm url for elixir module" do
      expect(docs_url(source)).to eq(expected_url)
    end

    context "function docs" do
      let :source, do: {:function, {ESpec, {:add_spec, 1}}}
      let :expected_url, do: "https://hexdocs.pm/espec/#{module_version}/ESpec.html#add_spec/1"

      it "returns hex.pm url for elixir function" do
        expect(docs_url(source)).to eq(expected_url)
      end

      context "arity is not provided" do
        let :source, do: {:function, {ESpec, :add_spec}}
        let :expected_url, do: "https://hexdocs.pm/espec/#{module_version}/ESpec.html"

        it "ignores function and returns hex.pm url for module" do
          expect(docs_url(source)).to eq(expected_url)
        end
      end
    end
  end
end

