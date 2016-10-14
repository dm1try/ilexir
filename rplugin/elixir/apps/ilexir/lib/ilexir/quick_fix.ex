defmodule Ilexir.QuickFix do
  use GenServer
  import NVim.Session
  require Logger

  @highilight_group "Underlined"

  def start_link(args \\ [], _opts \\ []) do
    GenServer.start_link(__MODULE__, args, [name: __MODULE__])
  end

  def init(_args) do
    {:ok, %{items: []}}
  end

  def update_items(items, group \\ :default) do
    GenServer.call(__MODULE__, {:update_items, items, group})
  end

  def clear_items(group \\ :default) do
    GenServer.call(__MODULE__, {:clear_items, group})
  end

  def handle_call({:update_items, items, _group}, _from, state) do
    case vim_get_current_buffer do
      {:ok, active_buffer} ->

        buffer_clear_highlight(active_buffer, -1, 0, -1)

        qf_items = items_to_qf_param(items)
        vim_call_function("setqflist", [qf_items,"r", "Ilexir"])
        qf_window_size = length(items)
        vim_command("bo copen #{qf_window_size} | wincmd p")

        highlight_items(items, active_buffer)
      {:error, error} ->
        Logger.error("unable to retrive current buffer: #{inspect error}")
    end

    {:reply, :ok, state}
  end

  def handle_call({:clear_items, _group}, _from, state) do
    vim_call_function("setqflist", [[],"r", "Ilexir"])
    vim_command("cclose")

    {:ok, active_buffer} = vim_get_current_buffer
    buffer_clear_highlight(active_buffer, -1, 0, -1)
    {:reply, :ok, state}
  end

  defp highlight_item(%Ilexir.QuickFix.Item{location: %{line: line, col_start: col_start, col_end: col_end}}, buffer, highlight_id) do
    buffer_add_highlight(buffer, highlight_id, @highilight_group, line - 1, col_start, col_end)
  end

  defp highlight_items(items, buffer, highlight_id \\ -1) do
    Enum.each(items, fn(item)-> highlight_item(item, buffer, highlight_id) end)
  end

  defp item_to_qf_param(%Ilexir.QuickFix.Item{
    file: file, text: text, type: type,
    location: %Ilexir.QuickFix.Item.Location{line: line, col_start: col_start}})
  do
    %{filename: file, text: text, type: qf_type(type), lnum: line, col: col_start}
  end

  defp items_to_qf_param(items) when is_list(items) do
    Enum.map(items, &item_to_qf_param/1)
  end

  defp qf_type(:error), do: "E"
  defp qf_type(:warning), do: "W"
  defp qf_type(_any), do: "N"
end
