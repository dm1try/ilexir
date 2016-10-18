use Mix.Config

config :logger, level: :error

config :ilexir,
  host_app_runner: Ilexir.HostApp.DummyRunner

