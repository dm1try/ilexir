defmodule Ilexir.Xref.Server do
  @moduledoc """
  Holds the information about remote dispatches in compiled modules.
  """

  use GenServer

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts ++ [name: __MODULE__])
  end

  def get_dispatches(file) do
    GenServer.call(__MODULE__,{:get_dispatches, file})
  end

  def handle_call({:get_dispatches, file}, _from, state) do
    dispatches = get_in(state, [:files, file]) |> all_dispatches
    {:reply, dispatches, state}
  end

  def init(_args) do
    {:ok, %{files: %{}}}
  end

  def handle_info({:after_compile, {env, _obj_code}}, state) do
    {_, state} = get_and_update_in state, [:files, env.file], fn
      nil -> {nil, %{env.module => remote_dispatches(env.lexical_tracker)}}
      dispatches -> {dispatches, Map.merge(dispatches, %{env.module => remote_dispatches(env.lexical_tracker)})}
    end

    {:noreply, state}
  end

  defp all_dispatches(file_data) do
    Enum.reduce file_data, {%{}, %{}}, fn({_mod, {compile_dispatches, runtime_dispatches}}, {all_compile, all_runtime})->
      {Map.merge(all_compile, compile_dispatches), Map.merge(all_runtime, runtime_dispatches)}
    end
  end

  defp remote_dispatches(nil = _tracker_pid), do: []
  defp remote_dispatches(tracker_pid) do
    # haha, re-thinking this :)
    if Process.alive?(tracker_pid) do
      Kernel.LexicalTracker.remote_dispatches(tracker_pid)
    else
      []
    end
  end
end

