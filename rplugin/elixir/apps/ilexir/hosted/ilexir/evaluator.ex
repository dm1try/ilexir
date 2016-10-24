defmodule Ilexir.Evaluator do
  @moduledoc """
  Pre-saves bindings between evaluations and allows to manage them.
  Returns special `{:undefined, var}` for undefined vars on the evaluation.
  """
  use GenServer

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts ++ [name: __MODULE__])
  end

  def init(_args) do
    {:ok, %{bindings: []}}
  end

  def get_bindings() do
    GenServer.call(__MODULE__, :get_bindings)
  end

  def set_bindings(new_bindings) do
    GenServer.call(__MODULE__, {:set_bindings, new_bindings})
  end

  def add_bindings(bindings) do
    GenServer.call(__MODULE__, {:add_bindings, bindings})
  end

  def eval_string(string, opts \\ []) do
    GenServer.call(__MODULE__, {:eval_string, string, opts})
  end

  def handle_call({:eval_string, string, opts}, _from, %{bindings: bindings} = state) do
    env = Keyword.get(opts, :env, [])

    {response, bindings} = do_eval(string, bindings, env)

    {:reply, response, %{state | bindings: bindings}}
  end

  def handle_call(:get_bindings, _from, state) do
    {:reply, state.bindings, state}
  end

  def handle_call({:set_bindings, bindings}, _from, state) when is_list(bindings) do
    state = %{state | bindings: bindings}
    {:reply, state.bindings, state}
  end

  def handle_call({:add_bindings, bindings}, _from, state) when is_list(bindings) do
    state = %{state | bindings: state.bindings ++ bindings}
    {:reply, state.bindings, state}
  end

  defp do_eval(string, bindings, env) do
    try do
      {result, bindings} = Code.eval_string(string, bindings, env)
      {{:ok, result}, bindings}
    rescue
      error in CompileError ->
        case Regex.named_captures(~r/undefined function (?<var_name>\w+)\/./, error.description) do
          %{"var_name" => var} ->
            {{:undefined, var}, bindings}
          _ ->
            {{:error, error.description}, bindings}
        end
      any ->
        {{:error, "#{inspect any}"}, bindings}
    end
  end
end
