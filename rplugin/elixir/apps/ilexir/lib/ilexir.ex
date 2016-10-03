defmodule Ilexir do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Ilexir.HostAppManager, [], [])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
