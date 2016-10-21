defmodule Ilexir.QuickFixSpec do
  use ESpec, async: false
  alias Ilexir.QuickFix
  alias NVim.Session.Embed, as: EmbedSession

  import NVim.Session

  before do
    {:ok, embed_session} = EmbedSession.start_link(file: Ilexir.Fixtures.test_elixir_file_path)
    {:ok, quick_fix_pid} = QuickFix.start_link

    enable_underlined_highlighting()

    {:shared, embed_session: embed_session, quick_fix_pid: quick_fix_pid}
  end

  finally do
    GenServer.stop(shared.quick_fix_pid)
    EmbedSession.stop(shared.embed_session)
  end

  let :fix_text, do: "need a fix"
  let :error_line_number, do: 1

  let :fix_item do
    %QuickFix.Item{
      file: Ilexir.Fixtures.test_elixir_file_path,
      text: fix_text,
      type: :warning,
      location: %QuickFix.Item.Location{
        line: 1,
        col_start: 1,
        col_end: 10
      }
    }
  end

  it "fills the quickfix list and highlights errors" do
    expect(QuickFix.update_items([fix_item])).to eq(:ok)

    expect_qf_list_size(1)
    expect_qf_list_have_any?(fix_text)
    expect_error_line_is_highlighted()
  end

  it "clears the quickfix list and removes the highlights" do
    QuickFix.update_items([fix_item])

    expect(QuickFix.clear_items()).to eq(:ok)

    expect_qf_list_size(0)
    expect_error_line_is_not_highlighted()
  end

  context "items from different groups" do
    let :another_item, do: %{fix_item | text: "another fix"}
    let :another_item2, do: %{fix_item | text: "another fix 2"}

    it "updates only specific group" do
      QuickFix.update_items([fix_item], :first_group)
      QuickFix.update_items([another_item, another_item2], :second_group)

      expect_qf_list_size(3)

      QuickFix.update_items([], :second_group)

      expect_qf_list_size(1)
      expect_qf_list_have_any?(fix_text)
    end
  end

  defp enable_underlined_highlighting do
    {:ok, _} = vim_command("hi Underlined cterm=underline")
  end

  defp expect_qf_list_size(size) do
    {:ok, items} = vim_call_function("getqflist", [])
    expect(length(items)).to eq(size)
  end

  defp expect_qf_list_have_any?(text) do
    {:ok, items} = vim_call_function("getqflist", [])
    Enum.any?(items, &(&1["text"] == text))
  end

  defp expect_error_line_is_highlighted do
    {:ok, attr} = vim_call_function("screenattr", [error_line_number,8])
    expect(attr).not_to eq(0)
  end

  defp expect_error_line_is_not_highlighted do
    {:ok, attr} = vim_call_function("screenattr", [error_line_number,8])
    expect(attr).to eq(0)
  end
end
