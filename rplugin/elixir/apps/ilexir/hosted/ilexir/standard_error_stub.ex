defmodule Ilexir.StandardErrorStub do
  @moduledoc """
  Stubs :standard_error gen_server and allows cache warnings.
  Responsible for caching warnings during a compilation process.
  """

  use GenServer

  def with_stab_standard_error(callback) do
    old_ansi_enabled = :application.get_env(:elixir, :ansi_enabled)
    if old_ansi_enabled, do: :application.set_env(:elixir, :ansi_enabled, false)

    __MODULE__.clear()
    __MODULE__.register()

    try do
      callback.()
    after
      __MODULE__.unregister()
      if old_ansi_enabled, do: :application.set_env(:elixir, :ansi_enabled, true)
    end

     __MODULE__.warnings()
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], [name: :standard_error_stub])
  end

  def init(_args) do
    std_error_pid = Process.whereis(:standard_error)

    {:ok, %{messages: [], std_error_pid: std_error_pid}}
  end

  def clear do
    GenServer.call(:standard_error_stub, :clear)
  end

  def messages do
    GenServer.call(:standard_error_stub, :messages)
  end

  def warnings do
    GenServer.call(:standard_error_stub, :warnings)
  end

  def register do
    GenServer.call(:standard_error_stub, :register)
  end

  def unregister do
    GenServer.call(:standard_error, :unregister)
  end

  def handle_call(:register, _from, state) do
    Process.unregister(:standard_error)
    Process.unregister(:standard_error_stub)

    Process.register(self(), :standard_error)
    {:reply, :ok, state}
  end

  def handle_call(:unregister, _from, %{std_error_pid: std_error_pid} = state) do
    Process.unregister(:standard_error)

    Process.register(std_error_pid, :standard_error)
    Process.register(self(), :standard_error_stub)

    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  def handle_call(:messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:warnings, _from, state) do
    warnings = Enum.map(state.messages, fn({_,_, message})->
      lines = String.split(message, "\n")
      "warning: " <> text  = List.first(lines)
      line_with_file = Enum.find(lines, fn(line)-> line |> String.match?(~r/\S+:\d+/) end)
      [file, line] = if line_with_file do
        [_, file, line] = Regex.run(~r/(?<file>\S+):(?<line>\d+)/, line_with_file)
        [file, String.to_integer(line)]
      else
        ["nofile", 1]
      end
      %{file: file, text: text, line: line}
    end)
    {:reply, warnings, state}
  end

  def handle_info({:io_request, from, reply_as, request}, state) do
    send from, {:io_reply, reply_as, :ok}
    new_messages = state.messages ++ [request]
    {:noreply, %{state | messages: new_messages}}
  end
end
