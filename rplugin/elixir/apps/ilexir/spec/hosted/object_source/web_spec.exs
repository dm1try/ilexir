defmodule Ilexir.ObjectSource.WebSpec do
  use ESpec
  import Ilexir.ObjectSource.Web

  context "elixir core docs" do
    let :source, do: {:module, Enum}

    let :elixir_version, do: "1.3"
    let :expected_url, do: "http://elixir-lang.org/docs/v#{elixir_version()}/elixir/Enum.html"

    before do
      allow(Application).to accept(:spec, fn(:elixir, :vsn)-> '1.3.4' end)
      :ok
    end

    it "returns docs url for the module" do
      expect(docs_url(source())).to eq(expected_url())
    end

    context "function docs" do
      let :source, do: {:function, {Enum, {:any, 2}}}
      let :expected_url, do: "http://elixir-lang.org/docs/v#{elixir_version()}/elixir/Enum.html#any/2"

      it "returns docs url for the function" do
        expect(docs_url(source())).to eq(expected_url())
      end
    end
  end

  context "elixir external package module docs" do
    let :source, do: {:module, ESpec}
    let :module_version, do: Application.spec(:espec, :vsn)
    let :expected_url, do: "https://hexdocs.pm/espec/#{module_version()}/ESpec.html"

    it "returns hexdocs.pm url for elixir module" do
      expect(docs_url(source())).to eq(expected_url())
    end

    context "function docs" do
      let :source, do: {:function, {ESpec, {:add_spec, 1}}}
      let :expected_url, do: "https://hexdocs.pm/espec/#{module_version()}/ESpec.html#add_spec/1"

      it "returns hex.pm url for elixir function" do
        expect(docs_url(source())).to eq(expected_url())
      end

      context "arity is not provided" do
        let :source, do: {:function, {ESpec, :add_spec}}
        let :expected_url, do: "https://hexdocs.pm/espec/#{module_version()}/ESpec.html"

        it "ignores function and returns hex.pm url for module" do
          expect(docs_url(source())).to eq(expected_url())
        end
      end
    end
  end

  context "erlang core docs" do
    let :source, do: {:erlang_module, :timer}
    let :expected_url, do: "http://erlang.org/doc/man/timer.html"

    it "returns docs url for the module" do
      expect(docs_url(source())).to eq(expected_url())
    end

    context "function docs" do
      let :source, do: {:erlang_function, {:timer, {:send_after, 2}}}
      let :expected_url, do: "http://erlang.org/doc/man/timer.html#send_after-2"

      it "returns docs url for the function" do
        expect(docs_url(source())).to eq(expected_url())
      end
    end

    context "mod without compile info" do
      let :source, do: {:erlang_function, {:erlang, {:unique_integer, 0}}}
      let :expected_url, do: "http://erlang.org/doc/man/erlang.html#unique_integer-0"

      it "returns docs url for the function" do
        expect(docs_url(source())).to eq(expected_url())
      end
    end
  end
end

